# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingCycles::ProcessService do
  describe ".call" do
    subject(:result) { described_class.call(customer:) }

    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:, currency: "USD") }
    let(:plan) { create(:plan, organization:, amount_currency: "USD") }
    let(:subscription) { create(:subscription, organization:, customer:, plan:) }
    let(:rate_card) { create(:rate_card, organization:, currency: "USD") }
    let(:subscription_rate_card) do
      create(
        :subscription_rate_card,
        organization:,
        customer:,
        subscription:,
        rate_card:,
        units: 5
      )
    end
    let(:rate_card_rate) do
      create(
        :rate_card_rate,
        organization:,
        rate_card:,
        rate_properties: {"amount" => "30.00"}
      )
    end
    let(:rate_override) { create(:rate_override, organization:, rate_properties: {"amount" => "15.00"}) }
    let(:billing_cycle_rate_properties) { {"amount" => "15.00"} }
    let(:billing_cycle_pricing_unit) { nil }

    before do
      create(
        :billing_cycle,
        organization:,
        subscription:,
        customer:,
        subscription_rate_card:,
        rate_card_rate:,
        rate_override:,
        pricing_unit: billing_cycle_pricing_unit,
        rate_properties: billing_cycle_rate_properties,
        billing_at: Time.zone.parse("2026-08-31 23:59:59"),
        period_from: Time.zone.parse("2026-08-01"),
        period_to: Time.zone.parse("2026-08-31 23:59:59")
      )
    end

    it "prices the fee from the billing cycle rate override" do
      rate_override.update!(rate_properties: {"amount" => "20.00"})

      expect(result).to be_success

      invoice = result.invoices.sole
      fee = invoice.fees.sole

      expect(fee.amount_cents).to eq(7_500)
      expect(fee.unit_amount_cents).to eq(1_500)
      expect(fee.precise_unit_amount).to eq(15)
      expect(fee.rate_card_rate).to eq(rate_card_rate)
      expect(fee.rate_override).to eq(rate_override)
    end

    context "when a scheduled cycle has a pricing unit" do
      let(:pricing_unit) { create(:pricing_unit, organization:, code: "credits", short_name: "cr") }
      let(:rate_card) do
        create(
          :rate_card,
          organization:,
          currency: "USD",
          applied_pricing_unit_code: pricing_unit.code
        )
      end
      let(:rate_card_rate) do
        create(
          :rate_card_rate,
          organization:,
          rate_card:,
          rate_properties: {"amount" => "10.00"},
          applied_pricing_unit_conversion_rate: 0.5
        )
      end
      let(:rate_override) { nil }
      let(:billing_cycle_rate_properties) { {"amount" => "10.00"} }
      let(:billing_cycle_pricing_unit) { pricing_unit }

      before { pricing_unit }

      it "uses the cycle pricing unit to compute the fee" do
        expect(result).to be_success

        fee = result.invoices.sole.fees.sole
        expect(fee.amount_cents).to eq(2_500)
        expect(fee.pricing_unit_usage).to have_attributes(
          pricing_unit:,
          amount_cents: 5_000,
          conversion_rate: 0.5
        )
      end
    end
  end
end
