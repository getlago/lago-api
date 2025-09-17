# frozen_string_literal: true

require "rails_helper"

RSpec.describe FixedCharges::UpdateChildrenJob do
  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:add_on) { create(:add_on, organization:) }
  let(:fixed_charge) { create(:fixed_charge, plan:, add_on:) }

  let(:child_plan_1) { create(:plan, organization:, parent_id: plan.id) }
  let(:child_plan_2) { create(:plan, organization:, parent_id: plan.id) }
  let(:subscription_1) { create(:subscription, plan: child_plan_1) }
  let(:subscription_2) { create(:subscription, plan: child_plan_2, status: :terminated) }

  let(:child_fixed_charge_1) { create(:fixed_charge, plan: child_plan_1, add_on:, parent_id: fixed_charge.id) }
  let(:child_fixed_charge_2) { create(:fixed_charge, plan: child_plan_2, add_on:, parent_id: fixed_charge.id) }

  let(:params) do
    {
      charge_model: "standard",
      properties: {amount: "200"}
    }
  end

  let(:old_parent_attrs) { fixed_charge.attributes }

  before do
    subscription_1
    subscription_2
    child_fixed_charge_1
    child_fixed_charge_2
    allow(FixedCharges::UpdateChildrenBatchJob).to receive(:perform_later)
      .and_call_original
  end

  it "calls the batch job for active/pending subscriptions only" do
    described_class.perform_now(params:, old_parent_attrs:)

    expect(FixedCharges::UpdateChildrenBatchJob).to have_received(:perform_later)
      .with(
        child_ids: [child_fixed_charge_1.id],
        params:,
        old_parent_attrs:
      )
      .once
  end

  context "when fixed charge is not found" do
    let(:old_parent_attrs) { {"id" => "non-existent-id"} }

    it "does not call the batch job" do
      described_class.perform_now(params:, old_parent_attrs:)

      expect(FixedCharges::UpdateChildrenBatchJob).not_to have_received(:perform_later)
    end
  end

  context "when there are no children" do
    before do
      fixed_charge.children.destroy_all
    end

    it "does not call the batch job" do
      described_class.perform_now(params:, old_parent_attrs:)

      expect(FixedCharges::UpdateChildrenBatchJob).not_to have_received(:perform_later)
    end
  end
end
