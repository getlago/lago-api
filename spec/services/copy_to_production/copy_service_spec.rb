# frozen_string_literal: true

require "rails_helper"

RSpec.describe CopyToProduction::CopyService do
  subject(:result) { described_class.call(organization:, user:, item_type: "billable_metric", id:) }

  let(:production) { create(:organization, :self_serve) }
  let(:sandbox) { create(:organization, :sandbox, production_organization: production, self_serve: true) }
  let(:organization) { sandbox }
  let(:user) { create(:user) }
  let(:production_roles) { %i[admin] }
  let(:id) { metric.id }

  let(:metric) do
    create(
      :billable_metric,
      organization: sandbox,
      code: "api_calls",
      name: "API calls",
      description: "Calls to the public API",
      aggregation_type: "sum_agg",
      field_name: "amount",
      rounding_function: "round",
      rounding_precision: 2
    )
  end

  before do
    create(:membership, user:, organization: production, roles: production_roles)
    create(:membership, user:, organization: sandbox, roles: %i[admin])
    create(:billable_metric_filter, billable_metric: metric, key: "region", values: %w[eu us])
    create(:billable_metric_filter, billable_metric: metric, key: "tier", values: %w[free paid])
  end

  it "copies the billable metric and its filters to production" do
    expect { result }.to change { production.billable_metrics.count }.by(1)

    copy = production.billable_metrics.find_by(code: "api_calls")
    expect(result).to be_success
    expect(result.item).to eq(CopyToProduction::BaseService::Entry.new(item_type: "billable_metric", record: copy))
    expect(result.copied_items).to eq([result.item])
    expect(result.reused_items).to eq([])
    expect(copy).to have_attributes(
      name: "API calls",
      description: "Calls to the public API",
      aggregation_type: "sum_agg",
      field_name: "amount",
      rounding_function: "round",
      rounding_precision: 2,
      recurring: false
    )
    expect(copy.filters.map { [it.key, it.values, it.organization_id] })
      .to eq([["region", %w[eu us], production.id], ["tier", %w[free paid], production.id]])
  end

  it "keeps the sandbox metric" do
    result

    expect(sandbox.billable_metrics.find_by(code: "api_calls")).to eq(metric)
    expect(metric.reload.filters.count).to eq(2)
  end

  it "sends the billable_metric.created webhook of production" do
    result

    expect(SendWebhookJob).to have_been_enqueued.with("billable_metric.created", result.item.record)
  end

  it "restores the membership of the context" do
    CurrentContext.membership = "membership/sandbox"

    result

    expect(CurrentContext.membership).to eq("membership/sandbox")
  end

  context "with activity logs", :capture_kafka_messages do
    let(:activity_log_env) do
      {
        "LAGO_CLICKHOUSE_ENABLED" => "true",
        "LAGO_KAFKA_BOOTSTRAP_SERVERS" => "kafka",
        "LAGO_KAFKA_ACTIVITY_LOGS_TOPIC" => "activity_logs"
      }
    end

    before do
      stub_const("ENV", ENV.to_h.merge(activity_log_env))
      CurrentContext.source = "graphql"
    end

    it "logs the creation and the copy in production, attributed to the user" do
      result

      logs = kafka_messages.map { JSON.parse(it[:payload]) }
      expect(logs.map { it.slice("activity_type", "organization_id", "resource_id", "user_id") }).to match_array(
        %w[billable_metric.created billable_metric.copied_to_production].map do |activity_type|
          {
            "activity_type" => activity_type,
            "organization_id" => production.id,
            "resource_id" => result.item.record.id,
            "user_id" => user.id
          }
        end
      )
    end

    context "when the copy runs inside a caller's transaction" do
      it "logs after that commit, still attributed to the user" do
        CurrentContext.membership = "membership/caller"

        ApplicationRecord.transaction do
          result
          expect(kafka_messages).to be_empty
        end

        expect(kafka_messages.map { JSON.parse(it[:payload]).values_at("activity_type", "user_id") }).to match_array(
          [["billable_metric.created", user.id], ["billable_metric.copied_to_production", user.id]]
        )
        expect(CurrentContext.membership).to eq("membership/caller")
      end
    end

    context "when the copy fails" do
      before do
        allow(BillableMetricFilters::CreateOrUpdateBatchService).to receive(:call)
          .and_return(BaseService::Result.new.service_failure!(code: "filters_failed", message: "Filters failed"))
      end

      it "logs nothing" do
        expect(result).to be_failure
        expect(kafka_messages).to be_empty
      end
    end
  end

  describe "expression cache" do
    let(:cache_key) { BillableMetrics::ExpressionCacheService.new(production.id, "api_calls").cache_key }

    before { allow(Rails.cache).to receive(:delete).and_call_original }

    it "expires the production entry of the code after the commit of the copy" do
      ApplicationRecord.transaction do
        result
        expect(Rails.cache).not_to have_received(:delete).with(cache_key)
      end

      expect(Rails.cache).to have_received(:delete).with(cache_key)
    end
  end

  context "when production has a metric with the same code" do
    before { create(:billable_metric, organization: production, code: "api_calls") }

    it "copies nothing" do
      expect { result }.not_to change(BillableMetric, :count)

      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::ValidationFailure)
      expect(result.error.messages).to eq(code: ["value_already_exist"])
    end
  end

  context "when production has a deleted metric with the same code" do
    before { create(:billable_metric, organization: production, code: "api_calls", deleted_at: Time.current) }

    it "copies the metric" do
      expect { result }.to change { production.billable_metrics.count }.by(1)

      expect(result).to be_success
    end
  end

  context "when the organization is a production" do
    let(:organization) { production }

    it "refuses the copy" do
      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::ForbiddenFailure)
      expect(result.error.code).to eq("copy_to_production_sandbox_only")
    end
  end

  context "when the sandbox has no such metric" do
    let(:id) { create(:billable_metric, organization: production).id }

    it "answers not found" do
      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::NotFoundFailure)
      expect(result.error.message).to eq("billable_metric_not_found")
    end
  end

  context "when the user is not an admin of production" do
    let(:production_roles) { %i[finance] }

    it "refuses the copy" do
      expect { result }.not_to change(BillableMetric, :count)

      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::ForbiddenFailure)
      expect(result.error.code).to eq("copy_to_production_admin_only")
    end
  end

  context "when the user is not a member of production" do
    before { production.memberships.update_all(status: :revoked, revoked_at: Time.current, updated_at: Time.current) } # rubocop:disable Rails/SkipsModelValidations

    it "refuses the copy" do
      expect(result).to be_failure
      expect(result.error.code).to eq("copy_to_production_admin_only")
    end
  end

  context "when production waits for a payment method" do
    include_context "with self-serve enabled"

    before { production.update!(activation_status: "pending_payment_method") }

    it "refuses the copy" do
      expect { result }.not_to change(BillableMetric, :count)

      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::ForbiddenFailure)
      expect(result.error.code).to eq("organization_inactive")
    end
  end

  context "when the copy fails after the metric is created" do
    before do
      allow(BillableMetricFilters::CreateOrUpdateBatchService).to receive(:call).and_wrap_original do |original, **args|
        original.call(**args)
        BaseService::Result.new.service_failure!(code: "filters_failed", message: "Filters failed")
      end
    end

    it "leaves production unchanged" do
      expect { result }.not_to change(BillableMetric.with_discarded, :count)

      expect(BillableMetricFilter.with_discarded.where(organization: production)).to be_empty
      expect(result).to be_failure
      expect(result.error.code).to eq("filters_failed")
      expect(SendWebhookJob).not_to have_been_enqueued
    end
  end

  context "with a custom aggregation metric" do
    let(:production) { create(:organization, :self_serve, custom_aggregation: true) }
    let(:metric) do
      create(:billable_metric, organization: sandbox, code: "api_calls", aggregation_type: "custom_agg",
        custom_aggregator: "def aggregate(event, previous_state, aggregation_properties); end")
    end

    it "refuses the copy" do
      expect { result }.not_to change(BillableMetric, :count)

      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::ForbiddenFailure)
      expect(result.error.code).to eq("copy_to_production_item_unsupported")
    end
  end

  context "when the copy fails inside a caller's transaction" do
    before do
      allow(BillableMetricFilters::CreateOrUpdateBatchService).to receive(:call)
        .and_return(BaseService::Result.new.service_failure!(code: "filters_failed", message: "Filters failed"))
    end

    it "rolls the copies back" do
      ApplicationRecord.transaction do
        expect(result).to be_failure
        expect(production.billable_metrics.with_discarded).to be_empty
      end
    end
  end

  context "when a concurrent write creates the code in production" do
    let(:constraint) { "index_billable_metrics_on_organization_id_and_code" }
    let(:database_result) { instance_double(PG::Result, error_field: constraint) }
    let(:database_error) { PG::UniqueViolation.new("duplicate value") }
    let(:write_error) { ActiveRecord::RecordNotUnique.new("duplicate value") }

    before do
      allow(database_error).to receive(:result).and_return(database_result)
      allow(BillableMetric).to receive(:create!) { raise write_error, cause: database_error }
    end

    it "answers value_already_exist on code" do
      expect(result).to be_failure
      expect(result.error.messages).to eq(code: ["value_already_exist"])
    end

    context "with another constraint" do
      let(:constraint) { "billable_metrics_pkey" }

      it "does not hide the database error" do
        expect { result }.to raise_error(ActiveRecord::RecordNotUnique)
      end
    end
  end

  context "with an item type that has a parent and dependencies" do
    let(:parent_item_class) do
      Class.new(CopyToProduction::Items::BillableMetricItem) do
        def self.name = "CopyToProduction::Items::ParentItem"
      end
    end

    let(:child_item_class) do
      Class.new(CopyToProduction::Items::BillableMetricItem) do
        def self.name = "CopyToProduction::Items::ChildItem"

        def parent(source)
          ["parent_item", sandbox.billable_metrics.find_by(code: "#{source.code}_parent")]
        end

        def dependencies(source)
          sandbox.billable_metrics.where(code: ["#{source.code}_reused", "#{source.code}_copied"]).order(:code)
            .map { ["billable_metric", it] }
        end
      end
    end

    let(:types) do
      CopyToProduction::Items::TYPES.merge(
        "parent_item" => "CopyToProduction::Items::ParentItem",
        "child_item" => "CopyToProduction::Items::ChildItem"
      )
    end

    let(:result) { described_class.call(organization:, user:, item_type: "child_item", id:) }

    before do
      stub_const("CopyToProduction::Items::ParentItem", parent_item_class)
      stub_const("CopyToProduction::Items::ChildItem", child_item_class)
      stub_const("CopyToProduction::Items::TYPES", types)

      create(:billable_metric, organization: sandbox, code: "api_calls_parent")
      create(:billable_metric, organization: sandbox, code: "api_calls_reused")
      create(:billable_metric, organization: sandbox, code: "api_calls_copied")
    end

    context "when the parent is live" do
      let(:live_parent) { create(:billable_metric, organization: production, code: "api_calls_parent") }
      let(:live_dependency) { create(:billable_metric, organization: production, code: "api_calls_reused") }

      before do
        live_parent
        live_dependency
      end

      it "copies the missing dependency before the item and reuses the others" do
        expect { result }.to change { production.billable_metrics.count }.by(2)

        expect(result.copied_items.map { [it.item_type, it.record.code, it.record.organization_id] }).to eq(
          [["billable_metric", "api_calls_copied", production.id], ["child_item", "api_calls", production.id]]
        )
        expect(result.reused_items.map(&:record)).to eq([live_parent, live_dependency])
      end
    end

    context "when a dependency to copy cannot be copied" do
      let(:live_parent) { create(:billable_metric, organization: production, code: "api_calls_parent") }

      before do
        live_parent
        sandbox.billable_metrics.find_by(code: "api_calls_copied")
          .update!(aggregation_type: "custom_agg", custom_aggregator: "aggregator")
      end

      it "refuses the copy" do
        expect { result }.not_to change { production.billable_metrics.count }

        expect(result).to be_failure
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
        expect(result.error.code).to eq("copy_to_production_item_unsupported")
      end
    end

    context "when the parent is not live" do
      it "refuses the copy" do
        expect { result }.not_to change(BillableMetric, :count)

        expect(result).to be_failure
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
        expect(result.error.code).to eq("copy_to_production_parent_missing")
      end
    end
  end
end
