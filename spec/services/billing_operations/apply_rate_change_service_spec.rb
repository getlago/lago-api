# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperations::ApplyRateChangeService do
  subject(:result) { described_class.call(customer:, rate_card_rate_id: rate.id) }

  let(:organization) { create(:organization, feature_flags: []) }
  let(:customer) { create(:customer, organization:, timezone: "UTC") }
  let(:contract) { create(:contract, organization:, customer:, started_at: Time.utc(2026, 11, 1)) }
  let(:product) { create(:product, :fixed, organization:) }
  let(:billing_timing) { "arrears" }
  let(:billing_scope) { "segment" }
  let(:rate_card) { create(:rate_card, organization:, product:, billing_timing:, currency: "USD") }
  let(:effective_from) { Time.utc(2026, 11, 15) }
  let(:old_rate) { create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 11, 1)) }
  let(:rate) { create(:rate_card_rate, organization:, rate_card:, effective_from:) }
  let(:clock) { Time.utc(2026, 12, 1) }
  let(:card) do
    create(:contract_rate_card, organization:, contract:, rate_card:, billing_scope:,
      effective_date: Date.new(2026, 11, 1), billing_anchor_date: Date.new(2026, 11, 1),
      next_billing_at: clock || Time.utc(2026, 12, 1))
  end

  around { |example| travel_to(Time.utc(2026, 11, 12)) { example.run } }

  before do
    card
    card.update!(next_billing_at: nil) if clock.nil?
    old_rate
    rate
  end

  it "wakes the clock at the rate boundary without creating operations or enqueuing processing" do
    expect { result }.not_to change(BillingOperation, :count)
    expect(result).to be_success
    expect(card.reload.next_billing_at).to eq(effective_from)
    expect(BillingOperations::ProcessJob).not_to have_been_enqueued
  end

  context "with cycle scope" do
    let(:billing_scope) { "cycle" }

    it "keeps the natural cycle close" do
      expect(result).to be_success
      expect(card.reload.next_billing_at).to eq(Time.utc(2026, 12, 1))
      expect(BillingOperation.where(contract_rate_card: card)).to be_empty
    end
  end

  context "with fixed advance" do
    let(:billing_timing) { "advance" }

    it "records the scheduled segment even when nothing has been billed" do
      expect { result }.to change(BillingOperation, :count).by(1)
      expect(result).to be_success
      reconciliation = card.billing_operations.sole
      expect(reconciliation).to have_attributes(action_type: "reconcile_advance_coverage", reason: "rate_change", processed_at: nil)
      expect(reconciliation.segments.pluck(:started_at, :ended_at, :rate_card_rate_id)).to eq([[effective_from, clock, rate.id]])
      expect(card.reload.next_billing_at).to eq(Time.utc(2026, 11, 1))
      expect(BillingOperations::ProcessJob).not_to have_been_enqueued
    end

    context "with two rate changes in the same cycle" do
      let(:billing_scope) { "cycle" }
      let(:later_rate) { create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 11, 20)) }

      it "saves a separate schedule snapshot for each change" do
        expect(result).to be_success
        first = card.billing_operations.sole
        described_class.call!(customer:, rate_card_rate_id: later_rate.id)
        second = card.billing_operations.where.not(id: first.id).sole

        expect(second).to have_attributes(action_type: first.action_type, coverage_started_at: first.coverage_started_at,
          coverage_ended_at: first.coverage_ended_at)
        expect(first.segments.pluck(:rate_card_rate_id)).to eq([old_rate.id, rate.id])
        expect(second.segments.pluck(:rate_card_rate_id)).to eq([old_rate.id, rate.id, later_rate.id])
      end
    end

    context "when November was already billed" do
      let(:reconciliations) { card.billing_operations.pending.where(action_type: BillingOperation::ACTION_TYPES.fetch(:reconcile_advance_coverage)) }
      let(:processed_at) { Time.utc(2026, 11, 1) }

      before do
        create(:billing_operation, organization:, customer:, contract_rate_card: card,
          action_type: BillingOperation::ACTION_TYPES.fetch(:renew_fixed_advance), reason: "contract_activation",
          billing_at: Time.utc(2026, 11, 1), target_cycle_started_at: Time.utc(2026, 11, 1),
          coverage_started_at: Time.utc(2026, 11, 1), coverage_ended_at: Time.utc(2026, 12, 1),
          processed_at:)
      end

      it "queues the changed segment once without moving the renewal or starting processing" do
        expect { result }.to change(reconciliations, :count).by(1)
        expect(result).to be_success
        reconciliation = reconciliations.sole
        expect(reconciliation).to have_attributes(
          reason: "rate_change", billing_at: effective_from, target_cycle_started_at: Time.utc(2026, 11, 1),
          coverage_started_at: effective_from, coverage_ended_at: Time.utc(2026, 12, 1), invoice_id: nil
        )
        described_class.call!(customer:, rate_card_rate_id: rate.id)
        expect(reconciliations.pluck(:id)).to eq([reconciliation.id])
        expect(card.reload.next_billing_at).to eq(Time.utc(2026, 12, 1))
        expect(BillingOperations::ProcessJob).not_to have_been_enqueued
      end

      context "when the clock is already earlier" do
        let(:clock) { Time.utc(2026, 11, 10) }

        it "still reconciles the purchased coverage" do
          expect { result }.to change(reconciliations, :count).by(1)
          expect(card.reload.next_billing_at).to eq(clock)
        end
      end

      context "when the change starts at the coverage end" do
        let(:effective_from) { Time.utc(2026, 12, 1) }

        it "records the next period selected by the schedule" do
          expect(result).to be_success
          expect(reconciliations.sole.segments.pluck(:started_at, :ended_at, :rate_card_rate_id))
            .to eq([[effective_from, Time.utc(2027, 1, 1), rate.id]])
        end
      end

      context "when the renewal is still pending" do
        let(:processed_at) { nil }

        it "records the same scheduled reconciliation while the renewal is pending" do
          expect { result }.to change(reconciliations, :count).by(1)
          expect(card.reload.next_billing_at).to eq(Time.utc(2026, 11, 1))
        end
      end

      context "when another price starts before the purchased coverage ends" do
        before { create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 11, 20)) }

        it "reconciles only the segment selected by Schedule" do
          expect(result).to be_success
          expect(reconciliations.sole).to have_attributes(coverage_started_at: effective_from, coverage_ended_at: Time.utc(2026, 11, 20))
        end
      end
    end
  end

  context "with metered arrears" do
    let(:product) { create(:product, organization:) }

    it "wakes the clock" do
      expect(result).to be_success
      expect(card.reload.next_billing_at).to eq(effective_from)
    end
  end

  context "when the clock is earlier than the change" do
    let(:clock) { Time.utc(2026, 11, 1) }

    it "does not skip an overdue wake" do
      expect(result).to be_success
      expect(card.reload.next_billing_at).to eq(clock)
    end
  end

  context "when the clock equals the change" do
    let(:clock) { effective_from }

    it "leaves the clock unchanged" do
      expect { result }.not_to change { card.reload.updated_at }
      expect(result).to be_success
      expect(card.next_billing_at).to eq(clock)
    end
  end

  context "when the clock is nil" do
    let(:clock) { nil }

    it "wakes an exhausted periodic card" do
      expect(result).to be_success
      expect(card.reload.next_billing_at).to eq(effective_from)
    end

    context "when the final coverage has already closed" do
      let(:contract) do
        create(:contract, organization:, customer:, started_at: Time.utc(2026, 11, 1), ended_at: Time.utc(2026, 11, 10))
      end

      before do
        create(:billing_operation, organization:, customer:, contract_rate_card: card,
          action_type: BillingOperation::ACTION_TYPES.fetch(:close_fixed_arrears), reason: "periodic_continuation",
          billing_at: Time.utc(2026, 11, 10), target_cycle_started_at: Time.utc(2026, 11, 1),
          coverage_started_at: Time.utc(2026, 11, 1), coverage_ended_at: Time.utc(2026, 11, 10),
          processed_at: Time.utc(2026, 11, 10))
      end

      it "keeps the clock nil when no obligation remains" do
        expect(result).to be_success
        expect(card.reload.next_billing_at).to be_nil
      end
    end
  end

  context "when the card has no periodic action" do
    let(:product) { create(:product, organization:) }
    let(:billing_timing) { "advance" }
    let(:clock) { nil }

    it "leaves the clock nil" do
      expect(card.periodic_billing_action).to be_nil
      expect(result).to be_success
      expect(card.reload.next_billing_at).to be_nil
      expect(BillingOperation.where(contract_rate_card: card)).to be_empty
    end

    context "with an existing clock" do
      let(:clock) { Time.utc(2026, 12, 1) }

      it "does not rewrite the clock" do
        expect(result).to be_success
        expect(card.reload.next_billing_at).to eq(clock)
      end
    end
  end

  context "when the rate was discarded" do
    before { rate.discard! }

    it "replans from the remaining rate" do
      expect(result).to be_success
      expect(card.reload.next_billing_at).to eq(Time.utc(2026, 12, 1))
    end
  end

  context "when the rate belongs to another organization" do
    let(:rate) { create(:rate_card_rate) }

    it "does not change the card" do
      expect(result).to be_success
      expect(card.reload.next_billing_at).to eq(clock)
    end
  end

  context "when the contract has not started" do
    let(:contract) { create(:contract, organization:, customer:, started_at: Time.utc(2026, 11, 13)) }

    it "does not change the card" do
      expect(result).to be_success
      expect(card.reload.next_billing_at).to eq(clock)
    end
  end

  context "when the contract is canceled" do
    let(:contract) { create(:contract, :canceled, organization:, customer:, started_at: Time.utc(2026, 11, 1)) }

    it "does not change the card" do
      expect(result).to be_success
      expect(card.reload.next_billing_at).to eq(clock)
    end
  end

  context "when termination wins the customer lock" do
    before do
      allow(Customers::LockService).to receive(:call!).and_wrap_original do |original, **kwargs, &block|
        contract.update!(status: :terminated, terminated_at: Time.current)
        original.call(**kwargs, &block)
      end
    end

    it "leaves the clock to termination planning" do
      expect(result).to be_success
      expect(card.reload.next_billing_at).to eq(clock)
    end
  end

  context "when the customer is missing" do
    subject(:result) { described_class.call(customer: nil, rate_card_rate_id: rate.id) }

    it "returns a not found failure" do
      expect(result).to be_failure
    end
  end

  context "when resetting the clock fails" do
    let(:failure) { BaseService::Result.new.single_validation_failure!(field: :base, error_code: "cannot_schedule") }

    before do
      allow(ContractRateCards::ResetBillingClockService).to receive(:call!)
        .and_raise(failure.error)
    end

    it "returns the reset failure without changing the clock" do
      expect(result).to be_failure
      expect(result.error).to eq(failure.error)
      expect(card.reload.next_billing_at).to eq(clock)
    end
  end
end
