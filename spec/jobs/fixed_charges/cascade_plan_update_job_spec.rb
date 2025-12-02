# frozen_string_literal: true

require "rails_helper"

RSpec.describe FixedCharges::CascadePlanUpdateJob do
  let(:organization) { create(:organization) }
  let(:parent_plan) { create(:plan, organization:) }
  let(:child_plan) { create(:plan, organization:, parent: parent_plan) }
  let(:add_on) { create(:add_on, organization:) }
  let(:timestamp) { Time.current.to_i }

  let(:parent_fixed_charge) do
    create(:fixed_charge, plan: parent_plan, add_on:, units: 10, pay_in_advance: true, properties: {amount: "10"})
  end

  let(:child_fixed_charge) do
    create(
      :fixed_charge,
      plan: child_plan,
      add_on:,
      parent: parent_fixed_charge,
      units: 10,
      pay_in_advance: true,
      properties: {amount: "10"}
    )
  end

  let(:cascade_payloads) do
    [{
      id: parent_fixed_charge.id,
      charge_model: "standard",
      units: 15,
      apply_units_immediately: true,
      properties: {amount: "10"}
    }]
  end

  before do
    child_fixed_charge
    allow(FixedCharges::CascadePlanUpdateService).to receive(:call!)
      .and_call_original
  end

  it "calls the cascade plan update service with correct parameters" do
    described_class.perform_now(
      parent_plan_id: parent_plan.id,
      child_plan_id: child_plan.id,
      cascade_payloads:,
      timestamp:
    )

    expect(FixedCharges::CascadePlanUpdateService).to have_received(:call!).with(
      child_plan: child_plan,
      child_fixed_charges: [child_fixed_charge],
      cascade_payloads:,
      timestamp:
    )
  end

  context "when parent plan has multiple fixed charges being updated" do
    let(:parent_fixed_charge2) do
      create(:fixed_charge, plan: parent_plan, add_on:, units: 5, pay_in_advance: true, properties: {amount: "20"})
    end

    let(:child_fixed_charge2) do
      create(
        :fixed_charge,
        plan: child_plan,
        add_on:,
        parent: parent_fixed_charge2,
        units: 5,
        pay_in_advance: true,
        properties: {amount: "20"}
      )
    end

    let(:cascade_payloads) do
      [
        {
          id: parent_fixed_charge.id,
          charge_model: "standard",
          units: 15,
          apply_units_immediately: true,
          properties: {amount: "10"}
        },
        {
          id: parent_fixed_charge2.id,
          charge_model: "standard",
          units: 8,
          apply_units_immediately: true,
          properties: {amount: "20"}
        }
      ]
    end

    before do
      child_fixed_charge2
    end

    it "includes all corresponding child fixed charges" do
      described_class.perform_now(
        parent_plan_id: parent_plan.id,
        child_plan_id: child_plan.id,
        cascade_payloads:,
        timestamp:
      )

      expect(FixedCharges::CascadePlanUpdateService).to have_received(:call!).with(
        child_plan: child_plan,
        child_fixed_charges: match_array([child_fixed_charge, child_fixed_charge2]),
        cascade_payloads:,
        timestamp:
      )
    end
  end

  context "when no child fixed charges exist for the cascade payloads" do
    let(:other_parent_fixed_charge) do
      create(:fixed_charge, plan: parent_plan, add_on:, units: 10, pay_in_advance: true, properties: {amount: "10"})
    end

    let(:cascade_payloads) do
      [{
        id: other_parent_fixed_charge.id, # This parent has no child in child_plan
        charge_model: "standard",
        units: 15,
        apply_units_immediately: true,
        properties: {amount: "10"}
      }]
    end

    it "does not call the service when no child fixed charges are found" do
      described_class.perform_now(
        parent_plan_id: parent_plan.id,
        child_plan_id: child_plan.id,
        cascade_payloads:,
        timestamp:
      )

      expect(FixedCharges::CascadePlanUpdateService).not_to have_received(:call!)
    end
  end
end
