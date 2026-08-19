# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingCycles::Fees::AmountsService do
  describe ".call" do
    subject(:result) do
      described_class.call(
        billing_cycle:,
        charge_model_result:,
        currency: Money::Currency.new("USD"),
        units:
      )
    end

    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:) }
    let(:plan) { create(:plan, organization:, amount_currency: "USD") }
    let(:subscription) { create(:subscription, organization:, customer:, plan:) }
    let(:product) { create(:product, :fixed, organization:) }
    let(:rate_card) { create(:rate_card, organization:, product:, currency: "USD") }
    let(:rate_card_rate) do
      create(
        :rate_card_rate,
        organization:,
        rate_card:,
        rate_model: "standard",
        rate_properties: {"amount" => "10"},
        applied_pricing_unit_conversion_rate:
      )
    end
    let(:subscription_rate_card) do
      create(
        :subscription_rate_card,
        organization:,
        customer:,
        subscription:,
        rate_card:,
        units:
      )
    end
    let(:billing_cycle) do
      create(
        :billing_cycle,
        organization:,
        customer:,
        subscription:,
        subscription_rate_card:,
        rate_card_rate:,
        pricing_unit:
      )
    end
    let(:charge_model_result) do
      BaseResult[:amount, :unit_amount].new.tap do |result|
        result.amount = BigDecimal("50")
        result.unit_amount = BigDecimal("10")
      end
    end
    let(:units) { 5 }
    let(:applied_pricing_unit_conversion_rate) { nil }
    let(:pricing_unit) { nil }

    context "without a pricing unit on the billing cycle" do
      it "returns fiat amount fields" do
        expect(result).to be_success
        expect(result.amount_cents).to eq(5_000)
        expect(result.precise_amount_cents).to eq(5_000)
        expect(result.unit_amount_cents).to eq(1_000)
        expect(result.precise_unit_amount).to eq(10)
        expect(result.pricing_unit_usage).to be_nil
      end
    end

    context "with a pricing unit on the billing cycle" do
      let(:pricing_unit) { create(:pricing_unit, organization:, code: "credits", short_name: "cr") }
      let(:rate_card) do
        create(
          :rate_card,
          organization:,
          product:,
          currency: "USD",
          applied_pricing_unit_code: pricing_unit.code
        )
      end
      let(:applied_pricing_unit_conversion_rate) { 0.5 }

      it "returns fiat amount fields converted from pricing unit amounts" do
        expect(result).to be_success
        expect(result.amount_cents).to eq(2_500)
        expect(result.precise_amount_cents).to eq(2_500)
        expect(result.unit_amount_cents).to eq(500)
        expect(result.precise_unit_amount).to eq(5)
        expect(result.pricing_unit_usage).to have_attributes(
          pricing_unit:,
          short_name: "cr",
          amount_cents: 5_000,
          precise_amount_cents: 5_000,
          unit_amount_cents: 1_000,
          precise_unit_amount: 10,
          conversion_rate: 0.5
        )
      end
    end
  end
end
