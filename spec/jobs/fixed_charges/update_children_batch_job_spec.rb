# frozen_string_literal: true

require "rails_helper"

RSpec.describe FixedCharges::UpdateChildrenBatchJob do
  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:add_on) { create(:add_on, organization:) }
  let(:fixed_charge) { create(:fixed_charge, plan:, add_on:) }
  let(:child_plan) { create(:plan, organization:, parent_id: plan.id) }
  let(:child_fixed_charge_1) { create(:fixed_charge, plan: child_plan, add_on:, parent: fixed_charge) }
  let(:child_fixed_charge_2) { create(:fixed_charge, plan: child_plan, add_on:, parent: fixed_charge) }
  let(:child_ids) { [child_fixed_charge_1.id, child_fixed_charge_2.id] }

  let(:params) do
    {
      charge_model: "standard",
      properties: {amount: "200"},
      units: 1
    }
  end

  let(:old_parent_attrs) { fixed_charge.attributes }

  before do
    child_fixed_charge_1
    child_fixed_charge_2

    allow(FixedCharges::UpdateChildrenService).to receive(:call!)
      .with(
        fixed_charge:,
        params:,
        old_parent_attrs:,
        child_ids:
      )
      .and_call_original
  end

  it "calls the service" do
    described_class.perform_now(
      child_ids:,
      params:,
      old_parent_attrs:
    )

    expect(FixedCharges::UpdateChildrenService).to have_received(:call!).once
  end
end
