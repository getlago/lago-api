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

    before do
      create(
        :billing_cycle,
        organization:,
        subscription:,
        customer:,
        subscription_rate_card:,
        rate_card_rate:,
        rate_override:,
        billing_at: Time.zone.parse("2026-08-31 23:59:59"),
        period_from: Time.zone.parse("2026-08-01"),
        period_to: Time.zone.parse("2026-08-31 23:59:59")
      )
    end

    it "prices the fee from the billing cycle rate override" do
      expect(result).to be_success

      invoice = result.invoices.sole
      fee = invoice.fees.sole

      expect(fee.amount_cents).to eq(7_500)
      expect(fee.unit_amount_cents).to eq(1_500)
      expect(fee.precise_unit_amount).to eq(15)
      expect(fee.rate_card_rate).to eq(rate_card_rate)
      expect(fee.rate_override).to eq(rate_override)
    end
  end
end
