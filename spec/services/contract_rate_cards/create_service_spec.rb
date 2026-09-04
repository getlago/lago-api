# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContractRateCards::CreateService do
  subject(:result) { described_class.call(contract:, params:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, currency: "EUR") }
  let(:plan) { nil }
  let(:contract) { create(:contract, :pending, organization:, customer:, plan:) }
  let(:rate_card) { create(:rate_card, organization:, currency: "EUR") }
  let(:params) { {rate_card_code: rate_card.code, units: "10"} }

  it "attaches the rate card with a default terminal phase" do
    expect(result).to be_success

    card = result.contract_rate_card
    expect(card.contract).to eq(contract)
    expect(card.rate_card).to eq(rate_card)
    expect(card.units).to eq(10)
    expect(card.effective_date).to eq(contract.started_at.in_time_zone(customer.applicable_timezone).to_date)
    expect(card.billing_anchor_date).to eq(contract.effective_billing_anchor_date)
    expect(card.next_billing_at).to eq(contract.started_at)
    expect(card.rate_phases.sole.code).to eq("default")
  end

  context "when a billing_anchor_date is provided" do
    let(:params) { super().merge(billing_anchor_date: "2026-03-01") }

    it "uses it over the contract anchor" do
      expect(result.contract_rate_card.billing_anchor_date).to eq(Date.new(2026, 3, 1))
    end
  end

  context "when the billing_anchor_date is malformed" do
    let(:params) { super().merge(billing_anchor_date: "not-a-date") }

    it "fails with an invalid value error" do
      expect(result).not_to be_success
      expect(result.error.messages[:billing_anchor_date]).to eq(["value_is_invalid"])
    end
  end

  context "when rate_phases are provided" do
    let(:params) do
      super().merge(rate_phases: [
        {code: "ramp", position: 1, billing_interval_cycle_count: 3},
        {code: "steady", position: 2}
      ])
    end

    it "materializes the provided sequence" do
      expect(result).to be_success
      expect(result.contract_rate_card.rate_phases.order(:position).map(&:code)).to eq(%w[ramp steady])
    end
  end

  context "when the contract is locked (active)" do
    let(:contract) { create(:contract, organization:, customer:, plan:) }

    it "fails with a contract_locked error" do
      expect(result).not_to be_success
      expect(result.error.messages[:contract]).to eq(["contract_locked"])
    end
  end

  context "when the rate card does not exist" do
    let(:params) { {rate_card_code: "unknown"} }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("rate_card")
    end
  end

  context "when the card currency does not match the contract currency" do
    let(:rate_card) { create(:rate_card, organization:, currency: "USD") }

    it "fails with a currency mismatch error" do
      expect(result).not_to be_success
      expect(result.error.messages[:currency]).to eq(["currency_does_not_match"])
    end
  end

  context "when the contract prices through a plan" do
    let(:plan) { create(:plan, :product_catalog, organization:, amount_currency: "EUR") }

    it "matches the currency against the plan" do
      expect(result).to be_success
    end
  end

  context "when the product slice is already priced" do
    before { create(:contract_rate_card, organization:, contract:, rate_card: create(:rate_card, organization:, currency: "EUR", product: rate_card.product)) }

    it "fails with a product_already_priced error" do
      expect(result).not_to be_success
      expect(result.error.messages[:rate_card]).to eq(["product_already_priced"])
    end
  end

  context "when the product's existing card has ended" do
    before do
      create(:contract_rate_card, organization:, contract:,
        rate_card: create(:rate_card, organization:, currency: "EUR", product: rate_card.product),
        effective_date: 3.days.ago, ended_date: 1.day.ago)
    end

    it "allows pricing the product again" do
      expect(result).to be_success
    end
  end
end
