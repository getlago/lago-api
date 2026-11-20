# frozen_string_literal: true

require "rails_helper"

RSpec.describe Charges::UpdateChildrenJob do
  let(:charge) { create(:standard_charge) }
  let(:child_plan1) { create(:plan, parent_id: charge.plan.id) }
  let(:child_plan2) { create(:plan, parent_id: charge.plan.id) }
  let(:child_charge) { create(:standard_charge, parent_id: charge.id, plan: child_plan1) }
  let(:child_charge2) { create(:standard_charge, parent_id: charge.id, plan: child_plan2) }
  let(:subscription) { create(:subscription, plan: child_plan1) }
  let(:subscription2) { create(:subscription, plan: child_plan2, status: :terminated) }
  let(:old_parent_attrs) { charge.attributes }
  let(:old_parent_applied_pricing_unit_attrs) { charge.filters.map(&:attributes) }
  let(:params) do
    {
      properties: {}
    }
  end

  before do
    child_plan1
    child_plan2
    child_charge
    subscription
    subscription2
  end

  it "calls the batch jobs" do
    described_class.perform_now(params:, old_parent_attrs:, old_parent_applied_pricing_unit_attrs:)

    expect(Charges::UpdateChildrenBatchJob).to have_been_enqueued.once
      .with(child_ids: [child_charge.id], params:, old_parent_attrs:, old_parent_applied_pricing_unit_attrs:)
  end

  context "when the children span several batches" do
    let(:charge) { create(:standard_charge, properties: {amount: "10"}) }
    let(:params) { {charge_model: "standard", properties: {amount: "20"}}.deep_stringify_keys }
    let(:child_charges) do
      create_list(:plan, 41, organization: charge.organization, parent_id: charge.plan.id).map do |child_plan|
        create(:subscription, plan: child_plan)
        create(
          :standard_charge,
          parent_id: charge.id,
          plan: child_plan,
          billable_metric: charge.billable_metric,
          properties: {amount: "10"}
        )
      end
    end

    before { child_charges }

    it "updates the children of every batch" do
      perform_enqueued_jobs do
        described_class.perform_now(params:, old_parent_attrs:, old_parent_applied_pricing_unit_attrs:)
      end

      expect(Charges::UpdateChildrenBatchJob).to have_been_performed.exactly(3).times
      expect(Charge.where(id: child_charges.map(&:id)).pluck(:properties).uniq).to eq([{"amount" => "20"}])
    end
  end
end
