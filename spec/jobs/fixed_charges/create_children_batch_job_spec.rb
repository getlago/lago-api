# frozen_string_literal: true

require "rails_helper"

RSpec.describe FixedCharges::CreateChildrenBatchJob do
  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:add_on) { create(:add_on, organization:) }
  let(:fixed_charge) { create(:fixed_charge, plan:, add_on:) }
  let(:child_plan) { create(:plan, organization:, parent_id: plan.id) }
  let(:child_ids) { [child_plan.id] }

  let(:payload) do
    {
      add_on_id: add_on.id,
      charge_model: "standard"
    }
  end

  before do
    child_plan
    allow(FixedCharges::CreateChildrenService).to receive(:call!)
      .with(child_ids:, fixed_charge:, payload:)
      .and_call_original
  end

  it "calls the service" do
    described_class.perform_now(child_ids:, fixed_charge:, payload:)

    expect(FixedCharges::CreateChildrenService).to have_received(:call!).once
  end
end
