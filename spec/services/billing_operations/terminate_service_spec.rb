# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperations::TerminateService do
  subject(:result) { described_class.call(contract:, timestamp:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, timezone: "UTC") }
  let(:started_at) { Time.utc(2026, 11, 1) }
  let(:timestamp) { Time.utc(2026, 11, 15) }
  let(:contract) do
    create(:contract, organization:, customer:, started_at:, status: :terminated, terminated_at: timestamp)
  end
  let(:product) { create(:product, :fixed, organization:) }
  let(:rate_card) do
    create(:rate_card, organization:, product:, billing_timing: "arrears", proration: true, currency: "USD")
  end
  let(:contract_rate_card) do
    create(:contract_rate_card, organization:, contract:, rate_card:, units: 1,
      effective_date: Date.new(2026, 11, 1), billing_anchor_date: Date.new(2026, 11, 1),
      next_billing_at: Time.utc(2026, 12, 1))
  end

  before do
    create(:rate_card_rate, organization:, rate_card:, effective_from: started_at,
      rate_model: "standard", rate_properties: {"amount" => "30"},
      billing_interval_count: 1, billing_interval_unit: "month")
    contract_rate_card
  end

  it "returns the final operation it creates" do
    expect(result).to be_success
    expect(result.billing_operations.sole).to have_attributes(
      action_type: "close_fixed_arrears", reason: "contract_termination",
      billing_at: timestamp, target_cycle_started_at: started_at, coverage_started_at: started_at, coverage_ended_at: timestamp
    )
    expect(result.billing_operations.sole.reload.segments.sole).to have_attributes(started_at:, ended_at: timestamp)
    expect(contract_rate_card.reload.next_billing_at).to eq(timestamp)
  end

  context "when the contract has no rate cards" do
    let(:contract_rate_card) { nil }

    it "returns an empty operation list" do
      expect(result).to be_success
      expect(result.billing_operations).to eq([])
    end
  end

  context "with termination billing boundaries" do
    let(:started_at) { Time.utc(2026, 1, 1) }
    let(:timestamp) { Time.utc(2026, 1, 15) }
    let(:ended_at) { nil }
    let(:billing_timing) { "arrears" }
    let(:cursor) { Time.utc(2026, 2, 1) }
    let(:contract) do
      create(:contract, :terminated, organization:, customer:, started_at:, terminated_at: timestamp, ended_at:)
    end
    let(:rate_card) do
      create(:rate_card, organization:, product:, billing_timing:, proration: true, currency: "USD")
    end
    let(:contract_rate_card) do
      create(:contract_rate_card, organization:, contract:, rate_card:, units: 1, next_billing_at: cursor,
        effective_date: Date.new(2026, 1, 1), billing_anchor_date: Date.new(2026, 1, 1))
    end

    before { travel_to timestamp }

    it "persists and bills the final partial cycle only once" do
      expect { result }.to change(BillingOperation, :count).by(1)
      expect(result.billing_operations.sole).to have_attributes(reason: "contract_termination", billing_at: timestamp)
      expect(contract_rate_card.reload.next_billing_at).to eq(timestamp)
      invoice = BillingOperations::ProcessService.call!(customer:, timestamp:).invoices.sole
      expect(invoice.total_amount_cents).to eq(1355) # $30 * 14 / 31 days.
      expect(invoice.billing_operations.sole).to have_attributes(reason: "contract_termination", processed_at: timestamp)
      expect(contract_rate_card.reload.next_billing_at).to be_nil
      expect(BillingOperations::ProcessService.call!(customer:, timestamp:).invoices).to be_empty
      expect(contract_rate_card.fees.count).to eq(1)
    end

    context "with an overdue close" do
      let(:timestamp) { Time.utc(2026, 2, 15) }

      it "bills the overdue cycle before the final partial cycle" do
        expect(result.billing_operations).to be_empty
        expect(contract_rate_card.reload.next_billing_at).to eq(cursor)
        BillingOperations::ScheduleService.call!(customer:, timestamp:)
        first = BillingOperations::ProcessService.call!(customer:, timestamp:).invoices.sole
        expect(first.total_amount_cents).to eq(3000)
        expect(contract_rate_card.reload.next_billing_at).to eq(timestamp)
        BillingOperations::ScheduleService.call!(customer:, timestamp:)
        final = BillingOperations::ProcessService.call!(customer:, timestamp:).invoices.sole
        expect(final.total_amount_cents).to eq(1500) # $30 * 14 / 28 days.
        expect(contract_rate_card.reload.next_billing_at).to be_nil
        expect(BillingOperations::ProcessService.call!(customer:, timestamp:).invoices).to be_empty
      end
    end

    context "with several overdue cycles" do
      let(:timestamp) { Time.utc(2026, 4, 15) }

      it "schedules and bills each remaining obligation without skipping coverage" do
        expect(result.billing_operations).to be_empty
        [Time.utc(2026, 2, 1), Time.utc(2026, 3, 1), Time.utc(2026, 4, 1), timestamp].each do |due_at|
          expect(contract_rate_card.reload.next_billing_at).to eq(due_at)
          BillingOperations::ScheduleService.call!(customer:, timestamp: due_at)
          expect(BillingOperations::ProcessService.call!(customer:, timestamp: due_at).invoices.sole.total_amount_cents)
            .to eq((due_at == timestamp) ? 1400 : 3000) # Final: $30 * 14 / 30 days.
        end
        expect(contract_rate_card.reload.next_billing_at).to be_nil
        expect(contract_rate_card.billing_operations.count).to eq(4)
        expect(contract_rate_card.billing_operations.pending).to be_empty
      end
    end

    context "when the natural end is earlier" do
      let(:ended_at) { Time.utc(2026, 1, 10) }

      it "retains the overdue natural-end obligation and does not extend coverage" do
        result
        expect(contract_rate_card.reload.next_billing_at).to eq(ended_at)
        BillingOperations::ScheduleService.call!(customer:, timestamp:)
        invoice = BillingOperations::ProcessService.call!(customer:, timestamp:).invoices.sole
        expect(invoice.total_amount_cents).to eq(871) # $30 * 9 / 31 days.
        expect(contract_rate_card.reload.next_billing_at).to be_nil
        expect(BillingOperations::ScheduleService.call!(customer:, timestamp:).billing_operations).to be_empty
        expect(BillingOperations::ProcessService.call!(customer:, timestamp:).invoices).to be_empty
        expect(contract_rate_card.fees.count).to eq(1)
      end
    end

    context "when the final cycle is already billed" do
      let(:ended_at) { Time.utc(2026, 1, 10) }

      before do
        create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: "close_fixed_arrears",
          billing_at: ended_at, target_cycle_started_at: started_at, processed_at: ended_at)
        contract_rate_card.update!(next_billing_at: nil)
      end

      it "does not schedule final coverage again" do
        expect { result }.not_to change(BillingOperation, :count)
        expect(contract_rate_card.reload.next_billing_at).to be_nil
      end
    end

    context "when the card has no cursor" do
      before { contract_rate_card.update!(next_billing_at: nil) }

      it "restores the outstanding clock without creating a termination operation" do
        expect { result }.not_to change(BillingOperation, :count)
        expect(contract_rate_card.reload.next_billing_at).to eq(timestamp)
      end
    end

    context "with advance billing" do
      let(:billing_timing) { "advance" }

      it "restores unbilled coverage from its start rather than keeping a later renewal" do
        expect(result.billing_operations).to be_empty
        expect(contract_rate_card.reload.next_billing_at).to eq(started_at)
        BillingOperations::ScheduleService.call!(customer:, timestamp:)
        invoice = BillingOperations::ProcessService.call!(customer:, timestamp:).invoices.sole
        expect(invoice.total_amount_cents).to eq(1355) # $30 * 14 / 31 days.
        expect(contract_rate_card.reload.next_billing_at).to be_nil
      end

      context "when renewal is exactly at termination" do
        let(:cursor) { timestamp }

        before do
          create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: "renew_fixed_advance",
            billing_at: started_at, target_cycle_started_at: started_at, processed_at: started_at)
        end

        it "clears a renewal starting at the exclusive contract end" do
          result
          expect(contract_rate_card.reload.next_billing_at).to be_nil
        end
      end
    end

    context "with pending reconciliations" do
      let(:due_reconciliation) do
        create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: "reconcile_advance_coverage",
          billing_at: timestamp, target_cycle_started_at: started_at)
      end
      let(:future_reconciliation) do
        create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: "reconcile_advance_coverage",
          billing_at: timestamp + 1.day, target_cycle_started_at: started_at)
      end

      before do
        due_reconciliation
        future_reconciliation
      end

      it "preserves due adjustments and cancels future ones" do
        result
        expect(due_reconciliation.reload.cancelled_at).to be_nil
        expect(future_reconciliation.reload).to have_attributes(cancelled_at: timestamp, cancellation_reason: "contract_termination")
      end

      context "when the card was discarded" do
        before { contract_rate_card.discard! }

        it "cancels future adjustments without restarting periodic billing" do
          result
          expect(due_reconciliation.reload.cancelled_at).to be_nil
          expect(future_reconciliation.reload).to have_attributes(cancelled_at: timestamp, cancellation_reason: "contract_termination")
          expect(contract_rate_card.reload.next_billing_at).to eq(cursor)
        end
      end
    end
  end
end
