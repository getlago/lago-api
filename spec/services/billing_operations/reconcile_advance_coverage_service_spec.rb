# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperations::ReconcileAdvanceCoverageService do
  subject(:result) { described_class.call(customer:, timestamp:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, timezone: "UTC") }
  let(:contract) { create(:contract, organization:, customer:, started_at: Time.utc(2026, 1, 1)) }
  let(:product) { create(:product, :fixed, organization:) }
  let(:rate_card) { create(:rate_card, organization:, product:, billing_timing: :arrears) }
  let(:rate) { create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 1)) }
  let(:card) do
    create(:contract_rate_card, organization:, contract:, rate_card:, units: 8,
      effective_date: Date.new(2026, 1, 1), next_billing_at: Time.utc(2026, 2, 1))
  end
  let(:timestamp) { Time.utc(2026, 2, 1) }
  let(:reason) { :contract_units_change }
  let(:change) do
    create(:billing_operation, organization:, customer:, contract_rate_card: card, action_type: "reconcile_advance_coverage",
      reason:, billing_at: Time.utc(2026, 1, 15), target_cycle_started_at: Time.utc(2026, 1, 1), units_before: 8, units_after: 5)
  end
  let(:periodic) do
    create(:billing_operation, organization:, customer:, contract_rate_card: card, action_type: "close_fixed_arrears",
      billing_at: timestamp, target_cycle_started_at: Time.utc(2026, 1, 1))
  end

  before do
    rate
    change
    periodic
  end

  it "completes only reconciliation and leaves the periodic obligation and cursor unchanged" do
    expect(result).to be_success
    expect(result.invoices).to be_empty
    expect(change.reload.processed_at).to eq(timestamp)
    expect(periodic.reload.processed_at).to be_nil
    expect(card.reload.next_billing_at).to eq(timestamp)
  end

  context "with deferred rate-change reconciliation" do
    let(:reason) { :rate_change }

    it "leaves the operation pending" do
      expect(result.invoices).to be_empty
      expect(change.reload.processed_at).to be_nil
    end
  end

  context "when a periodic obligation is due first" do
    before { periodic.update!(billing_at: Time.utc(2026, 1, 1)) }

    it "waits for periodic billing before processing reconciliation" do
      expect(result.processed_operation_ids).to be_empty
      expect(change.reload.processed_at).to be_nil
      expect(periodic.reload.processed_at).to be_nil
    end
  end

  context "when periodic billing and reconciliation have the same instant" do
    before { periodic.update!(billing_at: change.billing_at) }

    it "waits for the periodic operation" do
      expect(result.processed_operation_ids).to be_empty
      expect(change.reload.processed_at).to be_nil
    end
  end
end
