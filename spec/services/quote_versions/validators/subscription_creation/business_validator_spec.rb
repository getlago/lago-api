# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuoteVersions::Validators::SubscriptionCreation::BusinessValidator do
  subject(:validator) { described_class.new(result, quote_version:, billing_items:, scope:) }

  let(:result) { BaseService::Result.new }
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:quote) { create(:quote, organization:, customer:, order_type: :subscription_creation) }
  let(:quote_version) do
    create(
      :quote_version,
      quote:,
      organization:,
      currency: "EUR",
      start_date: Date.parse("2026-01-01"),
      end_date: Date.parse("2026-12-31")
    )
  end
  let(:plan) { create(:plan, organization:) }
  let(:charge) { create(:standard_charge, plan:) }
  let(:fixed_charge) { create(:fixed_charge, plan:) }
  let(:coupon) { create(:coupon, organization:) }
  let(:scope) { :update }

  let(:plan_item) do
    {
      "id" => plan.id,
      "localId" => "3d08b2df-4e4c-4d58-b415-a525c1663735",
      "payload" => {"code" => plan.code},
      "overrides" => plan_overrides
    }
  end
  let(:plan_overrides) do
    {
      "amountCents" => 500_000,
      "charges" => [{"id" => charge.id}],
      "fixedCharges" => [{"id" => fixed_charge.id}]
    }
  end

  let(:coupon_item) do
    {
      "id" => coupon.id,
      "localId" => "ba54903c-7bd5-4d40-8d51-45a5157005ff",
      "payload" => coupon_payload
    }
  end
  let(:coupon_payload) do
    {
      "code" => coupon.code,
      "couponType" => "fixed_amount",
      "amountCents" => 20_000
    }
  end

  let(:wallet_item) do
    {
      "localId" => "d9169d94-b322-4d70-a2b1-9e6a58e3f74a",
      "payload" => wallet_payload
    }
  end
  let(:wallet_payload) do
    {
      "paidCredits" => "100.0",
      "grantedCredits" => "10.0",
      "rateAmount" => "1.0",
      "recurringTransactionRules" => [recurring_rule]
    }
  end
  let(:recurring_rule) { {"trigger" => "interval", "interval" => "monthly", "method" => "fixed"} }

  let(:billing_items) do
    {
      "plans" => [plan_item],
      "coupons" => [coupon_item],
      "wallets" => [wallet_item]
    }
  end

  describe "#valid?" do
    context "with a valid quote version" do
      it "is valid for both scopes" do
        expect(described_class.new(BaseService::Result.new, quote_version:, billing_items:, scope: :update)).to be_valid
        expect(described_class.new(BaseService::Result.new, quote_version:, billing_items:, scope: :approve)).to be_valid
      end
    end

    context "when the currency is missing" do
      let(:quote_version) do
        create(
          :quote_version,
          quote:,
          organization:,
          currency: nil,
          start_date: Date.parse("2026-01-01"),
          end_date: Date.parse("2026-12-31")
        )
      end

      it "is valid at update scope" do
        expect(validator).to be_valid
      end

      context "when the scope is approve" do
        let(:scope) { :approve }

        it "requires the currency" do
          expect(validator).not_to be_valid
          expect(result.error.messages).to eq({currency: ["value_is_mandatory"]})
        end
      end
    end

    context "when the currency is not ISO 4217" do
      let(:quote_version) do
        create(
          :quote_version,
          quote:,
          organization:,
          currency: "DOUBLOON",
          start_date: Date.parse("2026-01-01"),
          end_date: Date.parse("2026-12-31")
        )
      end

      it "returns an invalid_currency error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({currency: ["invalid_currency"]})
      end
    end

    context "when the dates are missing" do
      let(:quote_version) { create(:quote_version, quote:, organization:, currency: "EUR") }

      it "is valid at update scope" do
        expect(validator).to be_valid
      end

      context "when the scope is approve" do
        let(:scope) { :approve }

        it "requires both dates" do
          expect(validator).not_to be_valid
          expect(result.error.messages).to eq(
            {
              start_date: ["value_is_mandatory"],
              end_date: ["value_is_mandatory"]
            }
          )
        end
      end
    end

    context "when the end date is before the start date" do
      let(:quote_version) do
        create(
          :quote_version,
          quote:,
          organization:,
          currency: "EUR",
          start_date: Date.parse("2026-12-31"),
          end_date: Date.parse("2026-01-01")
        )
      end

      it "returns an invalid_date_range error at update scope" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({start_date: ["invalid_date_range"]})
      end
    end

    context "when the end date equals the start date" do
      let(:quote_version) do
        create(
          :quote_version,
          quote:,
          organization:,
          currency: "EUR",
          start_date: Date.parse("2026-01-01"),
          end_date: Date.parse("2026-01-01")
        )
      end

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when the plan does not exist" do
      let(:plan_item) { super().merge("id" => "11111111-2222-3333-4444-555555555555") }

      it "returns a plan_not_found error and skips the override checks" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.id": ["plan_not_found"]})
      end
    end

    context "when the plan belongs to another organization" do
      let(:plan) { create(:plan) }
      let(:charge) { create(:standard_charge) }
      let(:fixed_charge) { create(:fixed_charge) }

      it "returns a plan_not_found error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.id": ["plan_not_found"]})
      end
    end

    context "when the plan is discarded" do
      before { plan.discard! }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when the charge override points at another plan's charge" do
      let(:charge) { create(:standard_charge, plan: create(:plan, organization:)) }

      it "returns a charge_not_found error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.overrides.charges.0.id": ["charge_not_found"]})
      end
    end

    context "when the charge is discarded" do
      before { charge.discard! }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when the fixed charge override points at another plan's fixed charge" do
      let(:fixed_charge) { create(:fixed_charge, plan: create(:plan, organization:)) }

      it "returns a fixed_charge_not_found error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.plans.0.overrides.fixedCharges.0.id": ["fixed_charge_not_found"]}
        )
      end
    end

    context "when the fixed charge is discarded" do
      before { fixed_charge.discard! }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when the coupon does not exist" do
      let(:coupon_item) { super().merge("id" => "11111111-2222-3333-4444-555555555555") }

      it "returns a coupon_not_found error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.coupons.0.id": ["coupon_not_found"]})
      end
    end

    context "when the coupon belongs to another organization" do
      let(:coupon) { create(:coupon) }

      it "returns a coupon_not_found error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.coupons.0.id": ["coupon_not_found"]})
      end
    end

    context "when the coupon is discarded" do
      before { coupon.discard! }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when a fixed_amount coupon currency differs from the version currency" do
      let(:coupon) { create(:coupon, organization:, amount_currency: "USD") }

      it "returns a currencies_does_not_match error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.coupons.0.id": ["currencies_does_not_match"]})
      end
    end

    context "when a percentage coupon currency differs from the version currency" do
      let(:coupon) do
        create(:coupon, organization:, coupon_type: "percentage", percentage_rate: 10, amount_currency: "USD")
      end
      let(:coupon_payload) do
        {
          "code" => coupon.code,
          "couponType" => "percentage",
          "percentageRate" => 10.0
        }
      end

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when the version currency is blank" do
      let(:quote_version) { create(:quote_version, quote:, organization:, currency: nil) }
      let(:coupon) { create(:coupon, organization:, amount_currency: "USD") }

      it "does not check the coupon currency" do
        expect(validator).to be_valid
      end
    end

    context "when the scope is approve" do
      let(:scope) { :approve }

      context "when a fixed_amount coupon payload has no amountCents" do
        let(:coupon_payload) { {"code" => coupon.code, "couponType" => "fixed_amount"} }

        it "requires amountCents" do
          expect(validator).not_to be_valid
          expect(result.error.messages).to eq({"billing_items.coupons.0.payload.amountCents": ["value_is_mandatory"]})
        end
      end

      context "when a percentage coupon payload has no percentageRate" do
        let(:coupon) { create(:coupon, organization:, coupon_type: "percentage", percentage_rate: 10) }
        let(:coupon_payload) { {"code" => coupon.code, "couponType" => "percentage"} }

        it "requires percentageRate" do
          expect(validator).not_to be_valid
          expect(result.error.messages).to eq(
            {"billing_items.coupons.0.payload.percentageRate": ["value_is_mandatory"]}
          )
        end
      end
    end

    context "when a fixed_amount coupon payload has no amountCents at update scope" do
      let(:coupon_payload) { {"code" => coupon.code, "couponType" => "fixed_amount"} }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when the wallet paidCredits is not a decimal" do
      let(:wallet_payload) { super().merge("paidCredits" => "abc") }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.wallets.0.payload.paidCredits": ["invalid_value"]})
      end
    end

    context "when the wallet grantedCredits is negative" do
      let(:wallet_payload) { super().merge("grantedCredits" => "-1") }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.wallets.0.payload.grantedCredits": ["invalid_value"]})
      end
    end

    context "when the wallet rateAmount is zero" do
      let(:wallet_payload) { super().merge("rateAmount" => "0") }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.wallets.0.payload.rateAmount": ["invalid_value"]})
      end
    end

    context "when the recurring rule trigger is interval without an interval" do
      let(:recurring_rule) { {"trigger" => "interval", "method" => "fixed"} }

      it "requires the interval" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.wallets.0.payload.recurringTransactionRules.0.interval": ["value_is_mandatory"]}
        )
      end
    end

    context "when the recurring rule trigger is threshold without thresholdCredits" do
      let(:recurring_rule) { {"trigger" => "threshold", "method" => "fixed"} }

      it "requires thresholdCredits" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.wallets.0.payload.recurringTransactionRules.0.thresholdCredits": ["value_is_mandatory"]}
        )
      end
    end

    context "when the recurring rule thresholdCredits is not a decimal" do
      let(:recurring_rule) { {"trigger" => "threshold", "method" => "fixed", "thresholdCredits" => "abc"} }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.wallets.0.payload.recurringTransactionRules.0.thresholdCredits": ["invalid_value"]}
        )
      end
    end

    context "when the recurring rule method is target without targetOngoingBalance" do
      let(:recurring_rule) { {"trigger" => "interval", "interval" => "monthly", "method" => "target"} }

      it "requires targetOngoingBalance" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.wallets.0.payload.recurringTransactionRules.0.targetOngoingBalance": ["value_is_mandatory"]}
        )
      end
    end

    context "when the recurring rule targetOngoingBalance is not a decimal" do
      let(:recurring_rule) do
        {"trigger" => "interval", "interval" => "monthly", "method" => "target", "targetOngoingBalance" => "abc"}
      end

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.wallets.0.payload.recurringTransactionRules.0.targetOngoingBalance": ["invalid_value"]}
        )
      end
    end

    context "when the recurring rule target is below the threshold" do
      let(:recurring_rule) do
        {"trigger" => "threshold", "method" => "target", "thresholdCredits" => "100", "targetOngoingBalance" => "50"}
      end

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.wallets.0.payload.recurringTransactionRules.0.targetOngoingBalance": ["invalid_value"]}
        )
      end
    end

    context "when the recurring rule target equals the threshold" do
      let(:recurring_rule) do
        {"trigger" => "threshold", "method" => "target", "thresholdCredits" => "100", "targetOngoingBalance" => "100"}
      end

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when the recurring rule paidCredits is not a decimal" do
      let(:recurring_rule) { super().merge("paidCredits" => "abc") }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.wallets.0.payload.recurringTransactionRules.0.paidCredits": ["invalid_value"]}
        )
      end
    end

    context "with errors on multiple coupons" do
      let(:billing_items) do
        super().merge(
          "coupons" => [
            coupon_item,
            coupon_item.merge("id" => "11111111-2222-3333-4444-555555555555")
          ]
        )
      end

      it "keys each error with the coupon index" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.coupons.1.id": ["coupon_not_found"]})
      end
    end
  end
end
