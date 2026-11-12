# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperations::ApplyTerminationService do
  subject(:result) { described_class.call(contract:, timestamp:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, timezone: "UTC") }
  let(:timestamp) { Time.utc(2026, 1, 15) }
  let(:ended_at) { nil }
  let(:contract) do
    create(:contract, :terminated, organization:, customer:, started_at: Time.utc(2026, 1, 1), terminated_at: timestamp, ended_at:)
  end
  let(:product) { create(:product, :fixed, organization:) }
  let(:billing_timing) { "arrears" }
  let(:rate_card) { create(:rate_card, organization:, product:, billing_timing:, currency: "USD", proration: true) }
  let(:cursor) { Time.utc(2026, 2, 1) }
  let(:contract_rate_card) do
    create(:contract_rate_card, organization:, contract:, rate_card:, next_billing_at: cursor, units: 1,
      effective_date: Date.new(2026, 1, 1), billing_anchor_date: Date.new(2026, 1, 1))
  end

  before do
    create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 1), rate_properties: {"amount" => "31"})
    contract_rate_card
  end

  it "moves the cursor to the final close without materializing future operations" do
    expect { result }.not_to change(BillingOperation, :count)
    expect(contract_rate_card.reload.next_billing_at).to eq(timestamp)
    invoice = BillingOperations::ProcessService.call!(customer:, timestamp:).invoices.sole
    expect(invoice.total_amount_cents).to eq(1400) # $31 * 14 / 31 days.
    expect(invoice.billing_operations.sole).to have_attributes(causation_type: "contract_termination", processed_at: timestamp)
    expect(contract_rate_card.reload.next_billing_at).to be_nil
    expect(BillingOperations::ProcessService.call!(customer:, timestamp:).invoices).to be_empty
  end

  context "with an overdue close" do
    let(:timestamp) { Time.utc(2026, 2, 15) }

    it "keeps the overdue cursor and continues through the final partial cycle" do
      result
      expect(contract_rate_card.reload.next_billing_at).to eq(cursor)
      first = BillingOperations::ProcessService.call!(customer:, timestamp:).invoices.sole
      expect(first.total_amount_cents).to eq(3100)
      expect(contract_rate_card.reload.next_billing_at).to eq(timestamp)
      final = BillingOperations::ProcessService.call!(customer:, timestamp:).invoices.sole
      expect(final.total_amount_cents).to eq(1550) # $31 * 14 / 28 days.
      expect(contract_rate_card.reload.next_billing_at).to be_nil
    end
  end

  context "with a future termination several cycles away" do
    let(:timestamp) { Time.utc(2026, 4, 15) }

    it "advances through every remaining cycle without precreating operations" do
      expect { result }.not_to change(BillingOperation, :count)
      [Time.utc(2026, 2, 1), Time.utc(2026, 3, 1), Time.utc(2026, 4, 1), timestamp].each do |due_at|
        expect(contract_rate_card.reload.next_billing_at).to eq(due_at)
        expect(BillingOperations::ProcessService.call!(customer:, timestamp: due_at).invoices.size).to eq(1)
      end
      expect(contract_rate_card.reload.next_billing_at).to be_nil
      expect(contract_rate_card.billing_operations.count).to eq(4)
      expect(contract_rate_card.billing_operations.pending).to be_empty
    end
  end

  context "when the contract's natural end is earlier" do
    let(:ended_at) { Time.utc(2026, 1, 10) }

    it "bills the final coverage at termination without extending service" do
      result
      expect(contract_rate_card.reload.next_billing_at).to eq(timestamp)
      invoice = BillingOperations::ProcessService.call!(customer:, timestamp:).invoices.sole
      expect(invoice.total_amount_cents).to eq(900) # $31 * 9 / 31 days.
      expect(contract_rate_card.reload.next_billing_at).to be_nil
    end
  end

  context "when the final cycle is already billed" do
    let(:cursor) { nil }
    let(:ended_at) { Time.utc(2026, 1, 10) }

    before do
      create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: "close_fixed_arrears",
        billing_at: ended_at, target_cycle_started_at: Time.utc(2026, 1, 1), processed_at: ended_at)
    end

    it "does not schedule the final coverage again at a later termination time" do
      result
      expect(contract_rate_card.reload.next_billing_at).to be_nil
    end
  end

  context "when the card was never scheduled" do
    let(:cursor) { nil }

    it "initializes the outstanding terminal close" do
      result
      expect(contract_rate_card.reload.next_billing_at).to eq(timestamp)
    end
  end

  context "with advance billing" do
    let(:billing_timing) { "advance" }

    it "clears renewals beyond the end" do
      result
      expect(contract_rate_card.reload.next_billing_at).to be_nil
    end

    context "with an overdue renewal" do
      let(:cursor) { Time.utc(2026, 1, 1) }

      it "preserves owed coverage and stops after its billing succeeds" do
        result
        expect(contract_rate_card.reload.next_billing_at).to eq(cursor)
        invoice = BillingOperations::ProcessService.call!(customer:, timestamp:).invoices.sole
        expect(invoice.total_amount_cents).to eq(1400) # $31 * 14 / 31 days.
        expect(contract_rate_card.reload.next_billing_at).to be_nil
      end
    end

    context "when renewal is exactly at termination" do
      let(:cursor) { timestamp }

      it "clears work starting at the exclusive contract end" do
        result
        expect(contract_rate_card.reload.next_billing_at).to be_nil
      end
    end
  end

  context "with pending reconciliations" do
    let(:due_reconciliation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: "reconcile_advance_coverage",
        billing_at: timestamp, target_cycle_started_at: Time.utc(2026, 1, 1))
    end
    let(:future_reconciliation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: "reconcile_advance_coverage",
        billing_at: timestamp + 1.day, target_cycle_started_at: Time.utc(2026, 1, 1))
    end

    before do
      due_reconciliation
      future_reconciliation
    end

    it "preserves due adjustments and cancels future ones" do
      result
      expect(due_reconciliation.reload.cancelled_at).to be_nil
      expect(future_reconciliation.reload).to have_attributes(cancelled_at: timestamp, cancelled_causation_type: "contract_termination")
    end

    context "when the card was discarded" do
      before { contract_rate_card.discard! }

      it "still cancels future adjustments without restarting periodic billing" do
        result
        expect(future_reconciliation.reload).to have_attributes(cancelled_at: timestamp, cancelled_causation_type: "contract_termination")
        expect(contract_rate_card.reload.next_billing_at).to eq(cursor)
      end
    end
  end
end
