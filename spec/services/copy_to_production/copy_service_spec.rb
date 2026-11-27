# frozen_string_literal: true

require "rails_helper"

RSpec.describe CopyToProduction::CopyService do
  subject(:result) { described_class.call(organization:, user:, item_type:, id:) }

  let(:production) { create(:organization, :self_serve) }
  let(:sandbox) { create(:organization, :sandbox, production_organization: production, self_serve: true) }
  let(:organization) { sandbox }
  let(:user) { create(:user) }
  let(:production_roles) { %i[admin] }
  let(:production_membership) { create(:membership, user:, organization: production, roles: production_roles) }
  let(:item_type) { "billable_metric" }
  let(:id) { metric.id }

  let(:metric) do
    create(
      :billable_metric,
      organization: sandbox,
      code: "api_calls",
      name: "API calls",
      description: "Calls to the public API",
      aggregation_type: "weighted_sum_agg",
      weighted_interval: "seconds",
      recurring: true,
      field_name: "amount",
      expression: "round(event.properties.amount * 2)",
      rounding_function: "round",
      rounding_precision: 2
    )
  end

  before do
    production_membership
    create(:membership, user:, organization: sandbox, roles: %i[admin])
    create(:billable_metric_filter, billable_metric: metric, key: "region", values: %w[eu us])
    create(:billable_metric_filter, billable_metric: metric, key: "tier", values: %w[free paid])
  end

  it "copies the billable metric and its filters to production" do
    expect { result }.to change { production.billable_metrics.count }.by(1)

    copy = production.billable_metrics.find_by(code: "api_calls")
    expect(result).to be_success
    expect(result.item).to eq(CopyToProduction::CopyService::Entry.new(item_type: "billable_metric", record: copy))
    expect(copy).to have_attributes(
      name: "API calls",
      description: "Calls to the public API",
      aggregation_type: "weighted_sum_agg",
      weighted_interval: "seconds",
      recurring: true,
      field_name: "amount",
      expression: "round(event.properties.amount * 2)",
      rounding_function: "round",
      rounding_precision: 2
    )
    expect(copy.filters.map { [it.key, it.values, it.organization_id] })
      .to eq([["region", %w[eu us], production.id], ["tier", %w[free paid], production.id]])
    expect(sandbox.billable_metrics.find_by(code: "api_calls").filters.count).to eq(2)
  end

  context "with a membership in the context" do
    around { |example| CurrentContext.set(membership: "membership/sandbox") { example.run } }

    it "restores it" do
      result

      expect(CurrentContext.membership).to eq("membership/sandbox")
    end
  end

  context "with activity logs", :capture_kafka_messages do
    let(:activity_log_env) do
      {
        "LAGO_CLICKHOUSE_ENABLED" => "true",
        "LAGO_KAFKA_BOOTSTRAP_SERVERS" => "kafka",
        "LAGO_KAFKA_ACTIVITY_LOGS_TOPIC" => "activity_logs"
      }
    end

    around { |example| CurrentContext.set(source: "graphql") { example.run } }

    before { stub_const("ENV", ENV.to_h.merge(activity_log_env)) }

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
    let(:production_membership) { nil }

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

  context "when a create service refuses after the metric is created", :capture_kafka_messages do
    before do
      stub_const("ENV", ENV.to_h.merge("LAGO_CLICKHOUSE_ENABLED" => "true", "LAGO_KAFKA_BOOTSTRAP_SERVERS" => "kafka",
        "LAGO_KAFKA_ACTIVITY_LOGS_TOPIC" => "activity_logs"))
      allow(BillableMetricFilters::CreateOrUpdateBatchService).to receive(:call).and_wrap_original do |original, **args|
        original.call(**args)
        BaseService::Result.new.service_failure!(code: "filters_failed", message: "Filters failed")
      end
    end

    it "answers its error and leaves production unchanged" do
      expect { result }.not_to change(BillableMetric.with_discarded, :count)

      expect(result).to be_failure
      expect(result.error.code).to eq("filters_failed")
      expect(BillableMetricFilter.with_discarded.where(organization: production)).to be_empty
      expect(SendWebhookJob).not_to have_been_enqueued
      expect(kafka_messages).to be_empty
    end
  end

  context "with an item type that has a parent and dependencies" do
    let(:item_type) { "child_item" }
    let(:refusals) { {} }
    let(:child_item_class) do
      refused_codes = refusals

      Class.new(CopyToProduction::Items::BillableMetricItem) do
        def self.name = "CopyToProduction::Items::ChildItem"

        def find_source(id) = sandbox.billable_metrics.find_by(id:)

        def find_existing(source) = production.billable_metrics.find_by(code: source.code)

        def parent(source)
          ["billable_metric", sandbox.billable_metrics.find_by(code: "#{source.code}_parent")]
        end

        def dependencies(source)
          sandbox.billable_metrics.where(code: ["#{source.code}_reused", "#{source.code}_copied"]).order(:code)
            .map { ["billable_metric", it] }
        end

        define_method(:refusal) { |source| refused_codes[source.code] }
      end
    end

    let(:live_parent) { create(:billable_metric, organization: production, code: "api_calls_parent") }
    let(:live_dependency) { create(:billable_metric, organization: production, code: "api_calls_reused") }

    before do
      stub_const("CopyToProduction::Items::ChildItem", child_item_class)
      stub_const("CopyToProduction::Items::TYPES", CopyToProduction::Items::TYPES.merge("child_item" => "CopyToProduction::Items::ChildItem"))

      create(:billable_metric, organization: sandbox, code: "api_calls_parent")
      create(:billable_metric, organization: sandbox, code: "api_calls_reused")
      create(:billable_metric, organization: sandbox, code: "api_calls_copied")
      live_parent
      live_dependency
    end

    it "copies the missing dependency before the item and reuses the others" do
      expect { result }.to change { production.billable_metrics.count }.by(2)

      expect(result.item.record).to eq(production.billable_metrics.find_by(code: "api_calls"))
      expect(production.billable_metrics.where(code: "api_calls_copied")).to exist
    end

    context "when an item to copy refuses the copy" do
      let(:refusals) { {"api_calls" => "copy_to_production_target_deleted"} }

      it "copies nothing" do
        expect { result }.not_to change { production.billable_metrics.count }

        expect(result).to be_failure
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
        expect(result.error.code).to eq("copy_to_production_target_deleted")
      end
    end

    context "when the parent is not live" do
      let(:live_parent) { nil }

      it "refuses the copy" do
        expect { result }.not_to change(BillableMetric, :count)

        expect(result).to be_failure
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
        expect(result.error.code).to eq("copy_to_production_parent_missing")
        expect(result.missing_parent.item_type).to eq("billable_metric")
        expect(result.missing_parent.record).to eq(sandbox.billable_metrics.find_by(code: "api_calls_parent"))
      end
    end
  end

  context "with a feature" do
    let(:item_type) { "feature" }
    let(:id) { feature.id }
    let(:feature) { create(:feature, organization: sandbox, code: "seats", name: "Seats", description: "Seats per workspace") }

    before do
      create(:privilege, feature:, code: "max", name: "Maximum", value_type: "integer", created_at: 2.days.ago)
      create(:privilege, feature:, code: "tier", value_type: "select", config: {select_options: %w[free pro]}, created_at: 1.day.ago)
      create(:privilege, feature:, code: "removed").discard!
    end

    it "copies the feature and its kept privileges to production" do
      expect { result }.to change { production.features.count }.by(1)

      copy = production.features.find_by(code: "seats")
      expect(result).to be_success
      expect(result.item).to eq(CopyToProduction::CopyService::Entry.new(item_type: "feature", record: copy))
      expect(copy).to have_attributes(name: "Seats", description: "Seats per workspace")
      expect(copy.privileges.order(:created_at, :id).map { [it.code, it.name, it.value_type, it.config, it.organization_id] }).to eq(
        [
          ["max", "Maximum", "integer", {}, production.id],
          ["tier", nil, "select", {"select_options" => %w[free pro]}, production.id]
        ]
      )
    end
  end

  context "with a fixed amount coupon on every metric" do
    let(:item_type) { "coupon" }
    let(:id) { coupon.id }
    let(:coupon) do
      create(
        :coupon,
        organization: sandbox,
        code: "launch",
        coupon_type: "fixed_amount",
        amount_cents: 1000,
        amount_currency: "EUR",
        percentage_rate: nil,
        frequency: "once",
        expiration: "no_expiration",
        limited_billable_metrics: false
      )
    end

    it "copies its amount and applies it to every metric" do
      expect { result }.not_to change { production.billable_metrics.count }

      copy = production.coupons.find_by(code: "launch")
      expect(result).to be_success
      expect(copy).to have_attributes(
        coupon_type: "fixed_amount",
        amount_cents: 1000,
        amount_currency: "EUR",
        percentage_rate: nil,
        frequency: "once",
        expiration: "no_expiration",
        limited_billable_metrics: false,
        limited_plans: false
      )
      expect(copy.coupon_targets).to be_empty
    end
  end

  context "with a coupon" do
    let(:item_type) { "coupon" }
    let(:id) { coupon.id }
    let(:coupon) do
      create(
        :coupon,
        organization: sandbox,
        code: "welcome",
        name: "Welcome",
        description: "First months off",
        coupon_type: "percentage",
        percentage_rate: 12.5,
        amount_cents: nil,
        amount_currency: nil,
        frequency: "recurring",
        frequency_duration: 3,
        expiration: "time_limit",
        expiration_at: 1.month.from_now.beginning_of_day,
        reusable: false,
        limited_billable_metrics: true
      )
    end

    let(:live_metric) { create(:billable_metric, organization: production, code: "seats") }
    let(:reused_metric_source) { create(:billable_metric, organization: sandbox, code: "seats") }
    let(:copied_metric_source) { create(:billable_metric, organization: sandbox, code: "storage") }

    before do
      create(:coupon_billable_metric, coupon:, billable_metric: reused_metric_source)
      create(:coupon_billable_metric, coupon:, billable_metric: copied_metric_source)
      live_metric
    end

    it "copies the coupon with its metric targets remapped to production" do
      expect { result }.to change { production.coupons.count }.by(1)
        .and change { production.billable_metrics.count }.by(1)

      copy = production.coupons.find_by(code: "welcome")
      copied_metric = production.billable_metrics.find_by(code: "storage")
      expect(result).to be_success
      expect(result.item).to eq(CopyToProduction::CopyService::Entry.new(item_type: "coupon", record: copy))
      expect(copy).to have_attributes(
        name: "Welcome",
        description: "First months off",
        coupon_type: "percentage",
        percentage_rate: 12.5,
        amount_cents: nil,
        frequency: "recurring",
        frequency_duration: 3,
        expiration: "time_limit",
        expiration_at: coupon.expiration_at,
        reusable: false,
        status: "active",
        limited_billable_metrics: true,
        limited_plans: false
      )
      expect(copy.coupon_targets.map { [it.billable_metric_id, it.organization_id] })
        .to contain_exactly([live_metric.id, production.id], [copied_metric.id, production.id])
    end

    context "when a coupon without expiration keeps a past date" do
      before { coupon.update!(expiration: "no_expiration", expiration_at: 1.day.ago) }

      it "copies the coupon without the date" do
        expect(result).to be_success
        expect(result.item.record).to have_attributes(status: "active", expiration: "no_expiration", expiration_at: nil)
      end
    end

    context "when one targeted metric is deleted in the sandbox" do
      before { copied_metric_source.discard! }

      it "copies the coupon limited to the kept metric" do
        expect { result }.not_to change { production.billable_metrics.count }

        expect(result).to be_success
        expect(result.item.record.limited_billable_metrics).to be(true)
        expect(result.item.record.coupon_targets.map(&:billable_metric_id)).to eq([live_metric.id])
      end
    end
  end
end
