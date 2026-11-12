# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContractRateCards::AdvanceBillingClockService do
  subject(:result) { described_class.call(operation:, resolution:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, timezone: "UTC") }
  let(:contract) { create(:contract, organization:, customer:, started_at: Time.utc(2026, 1, 1), **contract_attributes) }
  let(:contract_attributes) { {} }
  let(:product) { create(:product, :fixed, organization:) }
  let(:rate_card) { create(:rate_card, organization:, product:) }
  let(:contract_rate_card) do
    create(:contract_rate_card, organization:, contract:, rate_card:, next_billing_at: Time.utc(2026, 2, 1),
      effective_date: Date.new(2026, 1, 1), billing_anchor_date: Date.new(2026, 1, 1))
  end
  let(:operation) do
    create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: "close_fixed_arrears",
      billing_at: Time.utc(2026, 2, 1), target_cycle_started_at: Time.utc(2026, 1, 1), processed_at: Time.current)
  end
  let(:resolution) { BillingOperations::ResolveSegmentsService.call!(operation:) }

  before { create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 1)) }

  it "advances the cursor without creating a successor operation" do
    operation
    expect { result }.not_to change(BillingOperation, :count)
    expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 3, 1))
  end

  context "with a future termination" do
    let(:contract_attributes) { {status: :terminated, terminated_at: Time.utc(2026, 2, 15)} }

    it "continues through the remaining partial cycle" do
      result
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 2, 15))
    end
  end

  context "when the contract ends" do
    let(:contract_attributes) { {ended_at: Time.utc(2026, 2, 1)} }

    it "clears the cursor" do
      result
      expect(contract_rate_card.reload.next_billing_at).to be_nil
    end
  end

  context "with a reconciliation" do
    let(:operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:,
        action_type: "reconcile_advance_coverage", causation_type: "rate_change",
        billing_at: Time.utc(2026, 1, 15), target_cycle_started_at: Time.utc(2026, 1, 1), processed_at: Time.current)
    end
    let(:resolution) { nil }

    it "leaves the periodic cursor untouched" do
      result
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 2, 1))
    end
  end
end
