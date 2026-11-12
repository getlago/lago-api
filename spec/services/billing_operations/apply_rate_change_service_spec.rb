# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperations::ApplyRateChangeService do
  subject(:result) { described_class.call(customer:, rate_card_rate_id: new_rate.id) }

  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:customer) { create(:customer, organization:, timezone: "UTC") }
  let(:contract) { create(:contract, organization:, customer:, started_at: Time.utc(2026, 11, 1)) }
  let(:product) { create(:product, :fixed, organization:) }
  let(:billing_timing) { "arrears" }
  let(:rate_card) { create(:rate_card, organization:, product:, billing_timing:, proration: true, currency: "USD") }
  let(:card) do
    create(:contract_rate_card, organization:, contract:, rate_card:,
      effective_date: Date.new(2026, 11, 1), billing_anchor_date: Date.new(2026, 11, 1), units: 1)
  end
  let(:old_rate) do
    create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 11, 1),
      rate_properties: {"amount" => "30"})
  end
  let(:effective_from) { Time.utc(2026, 11, 15) }
  let(:earlier_rates) { [] }
  let(:new_rate) do
    create(:rate_card_rate, organization:, rate_card:, effective_from:, rate_properties: {"amount" => "60"})
  end
  let(:operation) do
    BillingOperations::CreateInitialOperationService.call!(contract_rate_card: card,
      causation_type: "contract_activation").billing_operations.sole
  end

  around { |example| travel_to(Time.utc(2026, 11, 15)) { example.run } }

  before do
    old_rate
    operation
    earlier_rates
    new_rate
  end

  it "cancels the close and bills each outstanding slice once through normal continuation" do
    expect(result).to be_success
    replacement = result.billing_operations.sole
    expect(operation.reload).to have_attributes(cancelled_at: Time.current, cancelled_causation_type: "rate_change", processed_at: nil)
    expect(replacement).to have_attributes(action_type: "close_fixed_arrears", causation_type: "rate_change",
      billing_at: effective_from, target_cycle_started_at: Time.utc(2026, 11, 1))
    expect(BillingOperations::ProcessJob).to have_been_enqueued.with(customer.id)

    first = BillingOperations::ProcessService.call!(customer:, timestamp: effective_from).invoices.sole
    expect(first.total_amount_cents).to eq(1400) # $30 * 14 / 30 days.
    expect(card.billing_operations.pending.sole.billing_at).to eq(Time.utc(2026, 12, 1))
    last = BillingOperations::ProcessService.call!(customer:, timestamp: Time.utc(2026, 12, 1)).invoices.sole
    expect(last.total_amount_cents).to eq(3200) # $60 * 16 / 30 days.
    expect(card.fees.order(:created_at).pluck(:amount_cents)).to eq([1400, 3200])
    expect(card.billing_operations.pending.sole.billing_at).to eq(Time.utc(2027, 1, 1))
    expect(BillingOperations::ProcessService.call!(customer:, timestamp: Time.utc(2026, 12, 1)).invoices).to be_empty
  end

  it "does not duplicate the replacement on repeated delivery" do
    result
    expect { described_class.call!(customer:, rate_card_rate_id: new_rate.id) }.not_to change(BillingOperation, :count)
    expect(card.billing_operations.pending.sole.billing_at).to eq(effective_from)
  end

  context "when replacement creation fails" do
    let(:failure) { BillingOperations::CreateService::Result.new.single_validation_failure!(field: :billing_at, error_code: "value_is_invalid") }

    before { allow(BillingOperations::CreateService).to receive(:call!).and_raise(BaseService::FailedResult.new(failure, "replacement failed")) }

    it "rolls back cancellation even when called inside another transaction" do
      ActiveRecord::Base.transaction do
        expect(result).not_to be_success
        expect(operation.reload.cancelled_at).to be_nil
        expect(card.billing_operations.count).to eq(1)
        expect(BillingOperations::ProcessJob).not_to have_been_enqueued
      end
    end
  end

  context "with several prices and out-of-order delivery" do
    let(:earlier_rate) do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 11, 10), rate_properties: {"amount" => "45"})
    end

    let(:earlier_rates) { [earlier_rate] }

    it "keeps the earliest outstanding boundary" do
      expect(result.billing_operations.sole.billing_at).to eq(Time.utc(2026, 11, 10))
      expect { described_class.call!(customer:, rate_card_rate_id: earlier_rate.id) }.not_to change(BillingOperation, :count)
      expect(card.billing_operations.pending.sole.billing_at).to eq(Time.utc(2026, 11, 10))
    end
  end

  context "when an earlier close is still pending" do
    before { operation.update!(billing_at: Time.utc(2026, 11, 10)) }

    it "preserves it for normal continuation" do
      expect(result.billing_operations).to be_empty
      expect(operation.reload.cancelled_at).to be_nil
    end
  end

  context "when an earlier slice was processed" do
    let(:earlier_rates) { [earlier_rate] }
    let(:earlier_rate) do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 11, 10), rate_properties: {"amount" => "45"})
    end

    before do
      earlier_rate
      create(:billing_operation, organization:, customer:, contract_rate_card: card,
        action_type: "close_fixed_arrears", billing_at: Time.utc(2026, 11, 10),
        target_cycle_started_at: Time.utc(2026, 11, 1), processed_at: Time.current)
    end

    it "replaces only the remaining close" do
      expect(result.billing_operations.sole.billing_at).to eq(effective_from)
    end
  end

  context "when the cycle was already billed" do
    before { operation.update!(processed_at: Time.current) }

    it "does not repartition processed coverage" do
      expect(result.billing_operations).to be_empty
      expect(operation.reload.cancelled_at).to be_nil
    end
  end

  context "when a rate starts exactly on the next cycle boundary" do
    let(:effective_from) { Time.utc(2026, 12, 1) }

    it "leaves the existing close unchanged" do
      expect(result.billing_operations).to be_empty
      expect(operation.reload.cancelled_at).to be_nil
    end
  end

  context "when a future cycle has no operation yet" do
    let(:effective_from) { Time.utc(2026, 12, 15) }

    it "does not seed that cycle" do
      expect { result }.not_to change(BillingOperation, :count)
      expect(result.billing_operations).to be_empty
    end
  end

  context "when the rate takes effect later in the represented cycle" do
    let(:effective_from) { Time.utc(2026, 11, 20) }

    it "persists the earlier close without processing it prematurely" do
      expect(result.billing_operations.sole.billing_at).to eq(effective_from)
      expect(BillingOperations::ProcessJob).not_to have_been_enqueued
    end
  end

  context "when another customer shares the rate card" do
    let(:other_customer) { create(:customer, organization:) }
    let(:other_contract) { create(:contract, organization:, customer: other_customer, started_at: Time.utc(2026, 11, 1)) }
    let(:other_card) do
      create(:contract_rate_card, organization:, contract: other_contract, rate_card:,
        effective_date: Date.new(2026, 11, 1), billing_anchor_date: Date.new(2026, 11, 1))
    end
    let(:other_operation) do
      create(:billing_operation, organization:, customer: other_customer, contract_rate_card: other_card,
        action_type: "close_fixed_arrears", billing_at: Time.utc(2026, 12, 1), target_cycle_started_at: Time.utc(2026, 11, 1))
    end

    before { other_operation }

    it "only replans the requested customer's operations" do
      expect(result.billing_operations.sole.customer_id).to eq(customer.id)
      expect(other_operation.reload.cancelled_at).to be_nil
      expect(other_card.billing_operations.count).to eq(1)
    end
  end

  context "when the effective date is after the contract ends" do
    let(:contract) do
      create(:contract, organization:, customer:, started_at: Time.utc(2026, 11, 1), ended_at: Time.utc(2026, 11, 10))
    end

    it "does not replan non-overlapping coverage" do
      expect(result.billing_operations).to be_empty
    end
  end

  context "when no chain exists" do
    let(:operation) { nil }

    it "does not seed initial billing" do
      card
      expect { result }.not_to change(BillingOperation, :count)
      expect(result.billing_operations).to be_empty
    end
  end

  context "when termination wins the customer lock" do
    before do
      allow(Customers::LockService).to receive(:call!).and_wrap_original do |original, **kwargs, &block|
        contract.update!(status: :terminated, terminated_at: Time.current)
        original.call(**kwargs, &block)
      end
    end

    it "leaves remaining work to termination planning" do
      expect(result.billing_operations).to be_empty
      expect(operation.reload.cancelled_at).to be_nil
    end
  end

  context "when the rate belongs to another organization" do
    let(:new_rate) { create(:rate_card_rate) }

    it "does not touch this customer's chain" do
      expect(result.billing_operations).to be_empty
      expect(operation.reload.cancelled_at).to be_nil
    end
  end

  context "when the rate was deleted" do
    before { new_rate.discard! }

    it "does nothing" do
      expect(result.billing_operations).to be_empty
      expect(operation.reload.cancelled_at).to be_nil
    end
  end

  context "when the card was deleted" do
    before { rate_card.discard! }

    it "does nothing" do
      expect(result.billing_operations).to be_empty
    end
  end

  context "when the applied card was deleted" do
    before { card.discard! }

    it "does nothing" do
      expect(result.billing_operations).to be_empty
    end
  end

  context "when the product is metered" do
    let(:product) { create(:product, organization:) }
    let(:rate_card) { create(:rate_card, organization:, product:, billing_timing:, proration: false) }

    it "does not change the metered chain" do
      expect(result.billing_operations).to be_empty
      expect(operation.reload.cancelled_at).to be_nil
    end
  end

  context "when the catalog is disabled" do
    before { organization.disable_feature_flag!(:product_catalog) }

    it "still replans the existing billing chain" do
      expect(result.billing_operations.sole).to have_attributes(
        action_type: "close_fixed_arrears", billing_at: effective_from
      )
      expect(operation.reload.cancelled_causation_type).to eq("rate_change")
    end
  end

  context "with a purchased fixed-advance cycle" do
    let(:billing_timing) { "advance" }
    let(:operation) do
      super().tap { BillingOperations::ProcessService.call!(customer:, timestamp: Time.utc(2026, 11, 1)) }
    end

    it "completes reconciliation without touching purchased coverage or the renewal" do
      purchased_fee = card.fees.sole.attributes
      renewal = card.billing_operations.pending.sole
      renewal_attributes = renewal.attributes

      expect(result).to be_success
      reconciliation = result.billing_operations.sole
      expect(reconciliation).to have_attributes(action_type: "reconcile_advance_coverage", causation_type: "rate_change",
        billing_at: effective_from, target_cycle_started_at: Time.utc(2026, 11, 1))
      expect(BillingOperations::ProcessService.call!(customer:, timestamp: effective_from).invoices).to be_empty
      expect(reconciliation.reload).to have_attributes(processed_at: effective_from, invoice_id: nil)
      expect(card.fees.sole.attributes).to eq(purchased_fee)
      expect(renewal.reload.attributes).to eq(renewal_attributes)
      expect(card.billing_operations.count).to eq(3)
      expect { described_class.call!(customer:, rate_card_rate_id: new_rate.id) }.not_to change(BillingOperation, :count)

      invoice = BillingOperations::ProcessService.call!(customer:, timestamp: Time.utc(2026, 12, 1)).invoices.sole
      expect(invoice.total_amount_cents).to eq(6000)
      expect(card.fees.order(:created_at).pluck(:amount_cents)).to eq([3000, 6000])
    end
  end
end
