# frozen_string_literal: true

require "rails_helper"

RSpec.describe CopyToProduction::PreviewService do
  subject(:result) { described_class.call(organization:, user:, item_type:, id: metric.id) }

  let(:production) { create(:organization, :self_serve) }
  let(:sandbox) { create(:organization, :sandbox, production_organization: production, self_serve: true) }
  let(:organization) { sandbox }
  let(:user) { create(:user) }
  let(:production_roles) { %i[admin] }
  let(:item_type) { "billable_metric" }
  let(:metric) { create(:billable_metric, organization: sandbox, code: "api_calls") }

  before do
    create(:membership, user:, organization: production, roles: production_roles)
    create(:membership, user:, organization: sandbox, roles: %i[admin])
    create(:billable_metric_filter, billable_metric: metric, key: "region", values: %w[eu us])
  end

  it "lists the metric to copy and leaves production unchanged" do
    expect { result }.not_to change { [BillableMetric.with_discarded.count, BillableMetricFilter.with_discarded.count] }

    expect(result).to be_success
    expect(result.copied_items).to eq([CopyToProduction::BaseService::Entry.new(item_type: "billable_metric", record: metric)])
    expect(result.reused_items).to eq([])
    expect(result.blocking_reason).to be_nil
    expect(result.missing_parent).to be_nil
    expect(result.refused_item).to be_nil
    expect(result.refusal_code).to be_nil
    expect(SendWebhookJob).not_to have_been_enqueued
    expect(SegmentTrackJob).not_to have_been_enqueued
  end

  context "with activity logs", :capture_kafka_messages do
    before do
      stub_const("ENV", ENV.to_h.merge("LAGO_CLICKHOUSE_ENABLED" => "true", "LAGO_KAFKA_BOOTSTRAP_SERVERS" => "kafka",
        "LAGO_KAFKA_ACTIVITY_LOGS_TOPIC" => "activity_logs"))
    end

    it "logs nothing" do
      result

      expect(kafka_messages).to be_empty
    end
  end

  context "when production has a metric with the same code" do
    before { create(:billable_metric, organization: production, code: "api_calls") }

    it "answers value_already_exist without listing items" do
      expect(result.blocking_reason).to eq("value_already_exist")
      expect(result.copied_items).to eq([])
      expect(result.refused_item).to be_nil
    end
  end

  context "when the user is not an admin of production" do
    let(:production_roles) { %i[manager] }

    it "answers copy_to_production_admin_only without listing items" do
      expect(result.blocking_reason).to eq("copy_to_production_admin_only")
      expect(result.copied_items).to eq([])
      expect(result.reused_items).to eq([])
    end
  end

  context "when the organization is a production" do
    let(:organization) { production }

    it "refuses the preview" do
      expect(result).to be_failure
      expect(result.error.code).to eq("copy_to_production_sandbox_only")
    end
  end

  context "when the create service refuses the copy" do
    let(:metric) do
      create(:billable_metric, organization: sandbox, code: "api_calls", aggregation_type: "custom_agg",
        custom_aggregator: "aggregator")
    end

    it "answers its error code and names the metric" do
      expect(result.blocking_reason).to eq("copy_to_production_item_refused")
      expect(result.refused_item).to eq(CopyToProduction::BaseService::Entry.new(item_type: "billable_metric", record: metric))
      expect(result.refusal_code).to eq("feature_unavailable")
      expect(result.refusal_field).to be_nil
    end

    context "with a validation error" do
      let(:production) { create(:organization, :self_serve, custom_aggregation: true) }

      it "answers its code and field" do
        expect(result.refusal_code).to eq("value_is_mandatory")
        expect(result.refusal_field).to eq("custom_aggregator")
      end
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

    let(:parent) { create(:billable_metric, organization: sandbox, code: "api_calls_parent") }
    let(:dependency) { create(:billable_metric, organization: sandbox, code: "api_calls_copied") }
    let(:live_parent) { create(:billable_metric, organization: production, code: "api_calls_parent") }
    let(:live_dependency) { create(:billable_metric, organization: production, code: "api_calls_reused") }

    before do
      stub_const("CopyToProduction::Items::ChildItem", child_item_class)
      stub_const("CopyToProduction::Items::TYPES", CopyToProduction::Items::TYPES.merge("child_item" => "CopyToProduction::Items::ChildItem"))

      parent
      dependency
      create(:billable_metric, organization: sandbox, code: "api_calls_reused")
      live_parent
      live_dependency
    end

    it "lists the items to copy and the production items it reuses" do
      expect(result.copied_items.map { [it.item_type, it.record] })
        .to eq([["billable_metric", dependency], ["child_item", metric]])
      expect(result.reused_items.map(&:record)).to eq([live_parent, live_dependency])
      expect(result.blocking_reason).to be_nil
    end

    context "when the create service refuses a dependency" do
      let(:dependency) do
        create(:billable_metric, organization: sandbox, code: "api_calls_copied", aggregation_type: "custom_agg",
          custom_aggregator: "aggregator")
      end

      it "names the dependency" do
        expect(result.blocking_reason).to eq("copy_to_production_item_refused")
        expect(result.refused_item.record).to eq(dependency)
      end
    end

    context "when an item to copy refuses the copy" do
      let(:refusals) { {"api_calls" => "copy_to_production_target_deleted"} }

      it "answers its refusal and names it" do
        expect(result.blocking_reason).to eq("copy_to_production_target_deleted")
        expect(result.refused_item).to eq(CopyToProduction::BaseService::Entry.new(item_type: "child_item", record: metric))
        expect(result.refusal_code).to be_nil
      end
    end

    context "when the parent is not live" do
      let(:live_parent) { nil }

      it "answers the missing parent" do
        expect(result.blocking_reason).to eq("copy_to_production_parent_missing")
        expect(result.missing_parent).to eq(CopyToProduction::BaseService::Entry.new(item_type: "billable_metric", record: parent))
      end
    end
  end
end
