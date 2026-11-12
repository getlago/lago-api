# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContractRateCards::InitializeBillingClockService do
  subject(:result) { described_class.call(contract_rate_card:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, timezone: "UTC") }
  let(:contract) { create(:contract, organization:, customer:, started_at: Time.utc(2026, 1, 1)) }
  let(:product) { create(:product, :fixed, organization:) }
  let(:billing_timing) { "arrears" }
  let(:rate_card) { create(:rate_card, organization:, product:, billing_timing:) }
  let(:contract_rate_card) do
    create(:contract_rate_card, organization:, contract:, rate_card:,
      effective_date: Date.new(2026, 1, 1), billing_anchor_date: Date.new(2026, 1, 1))
  end
  let(:effective_from) { Time.utc(2026, 1, 1) }

  before { create(:rate_card_rate, organization:, rate_card:, effective_from:) }

  it "sets the first close without creating an operation" do
    expect { result }.not_to change(BillingOperation, :count)
    expect(result).to be_success
    expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 2, 1))
  end

  context "with advance billing" do
    let(:billing_timing) { "advance" }

    it "sets the first renewal" do
      result
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 1, 1))
    end

    context "with a future first price" do
      let(:effective_from) { Time.utc(2026, 3, 15) }

      it "starts with the first priced coverage" do
        result
        expect(contract_rate_card.reload.next_billing_at).to eq(effective_from)
      end
    end
  end

  context "with an existing cursor" do
    before { contract_rate_card.update!(next_billing_at: Time.utc(2026, 3, 1)) }

    it "does not rewind billing on retries" do
      result
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 3, 1))
    end
  end

  context "with completed history" do
    before do
      create(:billing_operation, organization:, customer:, contract_rate_card:,
        action_type: "close_fixed_arrears", billing_at: Time.utc(2026, 2, 1),
        target_cycle_started_at: Time.utc(2026, 1, 1), processed_at: Time.current)
    end

    it "does not restart a completed lifecycle" do
      result
      expect(contract_rate_card.reload.next_billing_at).to be_nil
    end
  end

  context "with no periodic action" do
    let(:product) { create(:product, organization:) }
    let(:billing_timing) { "advance" }

    it "does not initialize a cursor" do
      result
      expect(contract_rate_card.reload.next_billing_at).to be_nil
    end
  end
end
