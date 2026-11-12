# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperations::ApplyRateChangeService do
  subject(:result) { described_class.call(customer:, rate_card_rate_id: new_rate.id) }

  let(:organization) { create(:organization, feature_flags: []) }
  let(:customer) { create(:customer, organization:, timezone: "UTC") }
  let(:contract) { create(:contract, organization:, customer:, started_at: Time.utc(2026, 11, 1)) }
  let(:product) { create(:product, :fixed, organization:) }
  let(:billing_timing) { "arrears" }
  let(:rate_card) { create(:rate_card, organization:, product:, billing_timing:, proration: true, currency: "USD") }
  let(:contract_rate_card) do
    create(:contract_rate_card, organization:, contract:, rate_card:,
      effective_date: Date.new(2026, 11, 1), billing_anchor_date: Date.new(2026, 11, 1), units: 1)
  end
  let(:old_rate) do
    create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 11, 1), rate_properties: {"amount" => "30"})
  end
  let(:effective_from) { Time.utc(2026, 11, 15) }
  let(:new_rate) do
    create(:rate_card_rate, organization:, rate_card:, effective_from:, rate_properties: {"amount" => "60"})
  end
  let(:earlier_rates) { [] }
  let(:initialize_clock) { ContractRateCards::InitializeBillingClockService.call!(contract_rate_card:) }

  around { |example| travel_to(Time.utc(2026, 11, 15)) { example.run } }

  before do
    old_rate
    initialize_clock
    earlier_rates
    new_rate
  end

  it "moves the cursor earlier without writing an unprocessed periodic operation" do
    expect { result }.not_to change(BillingOperation, :count)
    expect(result).to be_success
    expect(contract_rate_card.reload.next_billing_at).to eq(effective_from)
    expect(BillingOperations::ProcessJob).to have_been_enqueued.with(customer.id)

    first = BillingOperations::ProcessService.call!(customer:, timestamp: effective_from).invoices.sole
    expect(first.total_amount_cents).to eq(1400) # $30 * 14 / 30 days.
    expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 12, 1))
    last = BillingOperations::ProcessService.call!(customer:, timestamp: Time.utc(2026, 12, 1)).invoices.sole
    expect(last.total_amount_cents).to eq(3200) # $60 * 16 / 30 days.
    expect(contract_rate_card.billing_operations.order(:billing_at).pluck(:billing_at, :processed_at)).to eq([
      [effective_from, effective_from], [Time.utc(2026, 12, 1), Time.utc(2026, 12, 1)]
    ])
    expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2027, 1, 1))
  end

  it "keeps the same cursor on repeated delivery" do
    result
    expect { described_class.call!(customer:, rate_card_rate_id: new_rate.id) }.not_to change(BillingOperation, :count)
    expect(contract_rate_card.reload.next_billing_at).to eq(effective_from)
  end

  context "when another card fails after the first cursor was moved" do
    let(:other_contract) { create(:contract, organization:, customer:, started_at: contract.started_at) }
    let(:other_card) do
      create(:contract_rate_card, organization:, contract: other_contract, rate_card:,
        effective_date: contract_rate_card.effective_date, billing_anchor_date: contract_rate_card.billing_anchor_date,
        next_billing_at: Time.utc(2026, 12, 1))
    end
    let(:failure) { BaseService::Result.new.single_validation_failure!(field: :base, error_code: "cannot_schedule") }

    before do
      other_card
      calls = 0
      allow(BillingOperations::BuildScheduleService).to receive(:call!).and_wrap_original do |original, **attributes|
        calls += 1
        raise BaseService::FailedResult.new(failure, "cannot schedule") if calls == 2

        original.call(**attributes)
      end
    end

    it "rolls back both cursors and enqueues no processing" do
      expect(result).to be_failure
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 12, 1))
      expect(other_card.reload.next_billing_at).to eq(Time.utc(2026, 12, 1))
      expect(BillingOperation.count).to eq(0)
      expect(BillingOperations::ProcessJob).not_to have_been_enqueued
    end
  end

  context "with out-of-order rate jobs" do
    let(:earlier_rates) do
      [create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 11, 10), rate_properties: {"amount" => "45"})]
    end

    it "keeps the earliest outstanding boundary" do
      result
      described_class.call!(customer:, rate_card_rate_id: earlier_rates.sole.id)
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 11, 10))
    end
  end

  context "with an earlier unpaid cursor" do
    before { contract_rate_card.update!(next_billing_at: Time.utc(2026, 11, 10)) }

    it "preserves the owed work" do
      result
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 11, 10))
    end
  end

  context "with a completed November cycle" do
    before do
      BillingOperations::ProcessService.call!(customer:, timestamp: Time.utc(2026, 12, 1))
    end

    it "does not reopen billed coverage" do
      result
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2027, 1, 1))
    end
  end

  context "with no cursor" do
    let(:initialize_clock) { contract_rate_card }

    it "does not seed an initial chain" do
      result
      expect(contract_rate_card.reload.next_billing_at).to be_nil
      expect(contract_rate_card.billing_operations).to be_empty
    end
  end

  context "when the rate starts at an exact cycle boundary" do
    let(:effective_from) { Time.utc(2026, 12, 1) }

    it "leaves the cursor unchanged" do
      result
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 12, 1))
    end
  end

  context "with an unrepresented future cycle" do
    let(:effective_from) { Time.utc(2026, 12, 15) }

    it "leaves the earlier cursor unchanged" do
      result
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 12, 1))
    end
  end

  context "with future work in the represented cycle" do
    let(:effective_from) { Time.utc(2026, 11, 20) }

    it "moves the cursor without enqueueing processing prematurely" do
      result
      expect(contract_rate_card.reload.next_billing_at).to eq(effective_from)
      expect(BillingOperations::ProcessJob).not_to have_been_enqueued
    end
  end

  context "when termination wins the customer lock" do
    before do
      allow(Customers::LockService).to receive(:call!).and_wrap_original do |original, **kwargs, &block|
        contract.update!(status: :terminated, terminated_at: Time.current)
        original.call(**kwargs, &block)
      end
    end

    it "leaves the cursor to termination planning" do
      result
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 12, 1))
    end
  end

  context "when the rate belongs to another organization" do
    let(:new_rate) { create(:rate_card_rate) }

    it "leaves this customer's cursor unchanged" do
      result
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 12, 1))
    end
  end

  context "when the rate was deleted" do
    before { new_rate.discard! }

    it "does not move the cursor" do
      result
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 12, 1))
    end
  end

  context "when the product is metered" do
    let(:product) { create(:product, organization:) }
    let(:rate_card) { create(:rate_card, organization:, product:, billing_timing:, proration: false) }

    it "does not move the cursor" do
      result
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 12, 1))
    end
  end

  context "with purchased advance coverage" do
    let(:billing_timing) { "advance" }
    let(:initialize_clock) do
      super().tap { BillingOperations::ProcessService.call!(customer:, timestamp: Time.utc(2026, 11, 1)) }
    end

    it "persists an unprocessed reconciliation without moving the renewal cursor" do
      purchased_fee = contract_rate_card.fees.sole.attributes
      reconciliation = result.billing_operations.sole
      expect(reconciliation).to have_attributes(action_type: "reconcile_advance_coverage", billing_at: effective_from, processed_at: nil)
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 12, 1))
      expect(BillingOperations::ProcessJob).not_to have_been_enqueued
      expect(BillingOperations::ProcessService.call!(customer:, timestamp: effective_from).invoices).to be_empty
      expect(reconciliation.reload).to have_attributes(processed_at: nil, invoice_id: nil)
      expect(contract_rate_card.fees.sole.attributes).to eq(purchased_fee)
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 12, 1))
      expect { described_class.call!(customer:, rate_card_rate_id: new_rate.id) }.not_to change(BillingOperation, :count)
      invoice = BillingOperations::ProcessService.call!(customer:, timestamp: Time.utc(2026, 12, 1)).invoices.sole
      expect(invoice.total_amount_cents).to eq(6000)
      expect(contract_rate_card.billing_operations.count).to eq(3)
      expect(reconciliation.reload.processed_at).to be_nil
    end
  end
end
