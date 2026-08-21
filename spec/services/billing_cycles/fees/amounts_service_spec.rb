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
        applied_pricing_unit_conversion_rate:,
        min_amount_cents:
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
        pricing_unit:,
        proration_ratio:
      )
    end
    let(:charge_model_result) do
      BaseResult[:amount, :unit_amount].new.tap do |result|
        result.amount = BigDecimal("50")
        result.unit_amount = BigDecimal("10")
      end
    end
    let(:units) { 5 }
    let(:min_amount_cents) { 0 }
    let(:proration_ratio) { 1 }
    let(:applied_pricing_unit_conversion_rate) { nil }
    let(:pricing_unit) { nil }

    context "without a pricing unit on the billing cycle" do
      it "returns fiat amount fields" do
        expect(result).to be_success
        expect(result.amount).to have_attributes(
          amount_cents: 5_000,
          precise_amount_cents: 5_000,
          unit_amount_cents: 1_000,
          precise_unit_amount: 10,
          pricing_unit_usage: nil
        )
        expect(result.true_up_amount).to be_nil
      end

      context "with a minimum amount above the base amount" do
        let(:min_amount_cents) { 10_000 }

        it "returns fiat amount fields for the true-up amount" do
          expect(result).to be_success
          expect(result.true_up_amount).to have_attributes(
            amount_cents: 5_000,
            precise_amount_cents: 5_000,
            unit_amount_cents: 5_000,
            precise_unit_amount: 50,
            pricing_unit_usage: nil
          )
        end

        context "with proration" do
          let(:proration_ratio) { 0.75 }

          it "returns amount fields for the prorated true-up amount" do
            expect(result).to be_success
            expect(result.true_up_amount).to have_attributes(
              amount_cents: 2_500,
              precise_amount_cents: 2_500,
              unit_amount_cents: 2_500,
              precise_unit_amount: 25,
              pricing_unit_usage: nil
            )
          end
        end
      end

      context "with a minimum amount equal to the base amount" do
        let(:min_amount_cents) { 5_000 }

        it "does not return a true-up amount" do
          expect(result).to be_success
          expect(result.true_up_amount).to be_nil
        end
      end

      context "with a minimum amount below the base amount" do
        let(:min_amount_cents) { 4_000 }

        it "does not return a true-up amount" do
          expect(result).to be_success
          expect(result.true_up_amount).to be_nil
        end
      end

      context "with zero units" do
        let(:units) { 0 }

        it "returns zero unit amount fields" do
          expect(result).to be_success
          expect(result.amount).to have_attributes(
            amount_cents: 5_000,
            precise_amount_cents: 5_000,
            unit_amount_cents: 0,
            precise_unit_amount: 0,
            pricing_unit_usage: nil
          )
        end
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
        expect(result.amount).to have_attributes(
          amount_cents: 2_500,
          precise_amount_cents: 2_500,
          unit_amount_cents: 500,
          precise_unit_amount: 5
        )
        expect(result.amount.pricing_unit_usage).to have_attributes(
          pricing_unit:,
          short_name: "cr",
          amount_cents: 5_000,
          precise_amount_cents: 5_000,
          unit_amount_cents: 1_000,
          precise_unit_amount: 10,
          conversion_rate: 0.5
        )
        expect(result.true_up_amount).to be_nil
      end

      context "with a minimum amount above the converted base amount" do
        let(:min_amount_cents) { 10_000 }

        it "returns converted amount fields for the true-up amount" do
          expect(result).to be_success
          expect(result.true_up_amount).to have_attributes(
            amount_cents: 7_500,
            precise_amount_cents: 7_500,
            unit_amount_cents: 7_500,
            precise_unit_amount: 75
          )
          expect(result.true_up_amount.pricing_unit_usage).to have_attributes(
            pricing_unit:,
            amount_cents: 15_000,
            precise_amount_cents: 15_000,
            unit_amount_cents: 15_000,
            precise_unit_amount: 150,
            conversion_rate: 0.5
          )
        end

        context "with proration" do
          let(:proration_ratio) { 0.75 }

          it "returns converted amount fields for the prorated true-up amount" do
            expect(result).to be_success
            expect(result.true_up_amount).to have_attributes(
              amount_cents: 5_000,
              precise_amount_cents: 5_000,
              unit_amount_cents: 5_000,
              precise_unit_amount: 50
            )
            expect(result.true_up_amount.pricing_unit_usage).to have_attributes(
              pricing_unit:,
              amount_cents: 10_000,
              precise_amount_cents: 10_000,
              unit_amount_cents: 10_000,
              precise_unit_amount: 100,
              conversion_rate: 0.5
            )
          end
        end
      end

      context "with a minimum amount equal to the converted base amount" do
        let(:min_amount_cents) { 2_500 }

        it "does not return a true-up amount" do
          expect(result).to be_success
          expect(result.true_up_amount).to be_nil
        end
      end

      context "with a minimum amount below the converted base amount" do
        let(:min_amount_cents) { 2_000 }

        it "does not return a true-up amount" do
          expect(result).to be_success
          expect(result.true_up_amount).to be_nil
        end
      end
    end
  end
end
