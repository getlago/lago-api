# frozen_string_literal: true

require "rails_helper"

RSpec.describe CopyToProduction::PreviewService do
  subject(:result) { described_class.call(organization:, user:, item_type: "billable_metric", id: metric.id) }

  let(:production) { create(:organization, :self_serve) }
  let(:sandbox) { create(:organization, :sandbox, production_organization: production, self_serve: true) }
  let(:organization) { sandbox }
  let(:user) { create(:user) }
  let(:production_roles) { %i[admin] }
  let(:metric) { create(:billable_metric, organization: sandbox, code: "api_calls") }

  before do
    create(:membership, user:, organization: production, roles: production_roles)
    create(:membership, user:, organization: sandbox, roles: %i[admin])
  end

  it "lists the metric to copy without copying it" do
    expect { result }.not_to change { production.billable_metrics.count }

    expect(result).to be_success
    expect(result.copied_items).to eq([CopyToProduction::BaseService::Entry.new(item_type: "billable_metric", record: metric)])
    expect(result.reused_items).to eq([])
    expect(result.blocking_reason).to be_nil
    expect(result.missing_parent).to be_nil
  end

  context "when production has a metric with the same code" do
    before { create(:billable_metric, organization: production, code: "api_calls") }

    it "answers value_already_exist" do
      expect(result.blocking_reason).to eq("value_already_exist")
    end
  end

  context "when production has a deleted metric with the same code" do
    before { create(:billable_metric, organization: production, code: "api_calls", deleted_at: Time.current) }

    it "does not block the copy" do
      expect(result.blocking_reason).to be_nil
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

  context "when production waits for a payment method" do
    include_context "with self-serve enabled"

    before { production.update!(activation_status: "pending_payment_method") }

    it "answers organization_inactive without listing items" do
      expect(result.blocking_reason).to eq("organization_inactive")
      expect(result.copied_items).to eq([])
      expect(result.reused_items).to eq([])
    end
  end

  context "with a custom aggregation metric" do
    let(:metric) do
      create(:billable_metric, organization: sandbox, code: "api_calls", aggregation_type: "custom_agg",
        custom_aggregator: "aggregator")
    end

    it "answers copy_to_production_item_unsupported" do
      expect(result.blocking_reason).to eq("copy_to_production_item_unsupported")
    end
  end

  context "when the organization is a production" do
    let(:organization) { production }

    it "refuses the preview" do
      expect(result).to be_failure
      expect(result.error.code).to eq("copy_to_production_sandbox_only")
    end
  end

  context "with an item type whose dependency is live" do
    subject(:result) { described_class.call(organization:, user:, item_type: "child_item", id: metric.id) }

    let(:dependency) { create(:billable_metric, organization: sandbox, code: "api_calls_dependency") }
    let(:live_dependency) { create(:billable_metric, organization: production, code: "api_calls_dependency") }

    let(:child_item_class) do
      dependency_metric = dependency

      Class.new(CopyToProduction::Items::BillableMetricItem) do
        def self.name = "CopyToProduction::Items::ChildItem"

        define_method(:dependencies) { |_source| [["billable_metric", dependency_metric]] }
      end
    end

    before do
      live_dependency
      stub_const("CopyToProduction::Items::ChildItem", child_item_class)
      stub_const("CopyToProduction::Items::TYPES", CopyToProduction::Items::TYPES.merge("child_item" => "CopyToProduction::Items::ChildItem"))
    end

    it "lists the production item it reuses" do
      expect(result.reused_items).to eq([CopyToProduction::BaseService::Entry.new(item_type: "billable_metric", record: live_dependency)])
    end

    context "when the user is not an admin of production" do
      let(:production_roles) { %i[manager] }

      it "does not list it" do
        expect(result.blocking_reason).to eq("copy_to_production_admin_only")
        expect(result.copied_items).to eq([])
        expect(result.reused_items).to eq([])
      end
    end
  end

  context "with an item type whose parent is not live" do
    subject(:result) { described_class.call(organization:, user:, item_type: "child_item", id: metric.id) }

    let(:parent) { create(:billable_metric, organization: sandbox, code: "api_calls_parent") }

    let(:child_item_class) do
      parent_metric = parent

      Class.new(CopyToProduction::Items::BillableMetricItem) do
        def self.name = "CopyToProduction::Items::ChildItem"

        define_method(:parent) { |_source| ["billable_metric", parent_metric] }
      end
    end

    before do
      stub_const("CopyToProduction::Items::ChildItem", child_item_class)
      stub_const("CopyToProduction::Items::TYPES", CopyToProduction::Items::TYPES.merge("child_item" => "CopyToProduction::Items::ChildItem"))
    end

    it "answers the missing parent" do
      expect(result.blocking_reason).to eq("copy_to_production_parent_missing")
      expect(result.missing_parent).to eq(CopyToProduction::BaseService::Entry.new(item_type: "billable_metric", record: parent))
    end
  end
end
