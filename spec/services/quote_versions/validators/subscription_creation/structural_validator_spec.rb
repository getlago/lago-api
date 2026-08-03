# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuoteVersions::Validators::SubscriptionCreation::StructuralValidator do
  subject(:validator) { described_class.new(result, billing_items:, scope:) }

  let(:result) { BaseService::Result.new }
  let(:scope) { :update }

  let(:plan_item) do
    {
      "id" => "48e59220-6722-49c1-8cdf-eacd040e2a56",
      "localId" => "3d08b2df-4e4c-4d58-b415-a525c1663735",
      "type" => "plan",
      "payload" => plan_payload,
      "overrides" => plan_overrides
    }
  end
  let(:plan_payload) { {"code" => "enterprise"} }
  let(:plan_overrides) do
    {
      "amountCents" => 500_000,
      "charges" => [charge_override],
      "fixedCharges" => [fixed_charge_override]
    }
  end
  let(:charge_override) do
    {
      "id" => "9c4681ce-b915-486a-9d94-a294d444a89b",
      "properties" => {"amount" => "0.30"},
      "minAmountCents" => 10_000,
      "invoiceDisplayName" => "API calls"
    }
  end
  let(:fixed_charge_override) do
    {
      "id" => "e447e942-e21a-40fb-9e75-4bbc2a68c46b",
      "units" => "3",
      "properties" => {"amount" => "50"},
      "invoiceDisplayName" => "Seats"
    }
  end

  let(:coupon_item) do
    {
      "id" => "5c1f47bb-fbf8-4be6-b1a4-b1a26a0a2b78",
      "localId" => "ba54903c-7bd5-4d40-8d51-45a5157005ff",
      "type" => "coupon",
      "payload" => coupon_payload
    }
  end
  let(:coupon_payload) do
    {
      "code" => "ent_20",
      "couponType" => "fixed_amount",
      "amountCents" => 20_000,
      "amountCurrency" => "EUR",
      "frequency" => "once"
    }
  end

  let(:wallet_item) do
    {
      "localId" => "d9169d94-b322-4d70-a2b1-9e6a58e3f74a",
      "type" => "wallet",
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
  let(:recurring_rule) do
    {
      "trigger" => "interval",
      "interval" => "monthly",
      "method" => "fixed",
      "paidCredits" => "50.0",
      "grantedCredits" => "0"
    }
  end

  let(:billing_items) do
    {
      "plans" => [plan_item],
      "coupons" => [coupon_item],
      "wallets" => [wallet_item]
    }
  end

  describe "#valid?" do
    context "with a full valid payload" do
      it "is valid for both scopes" do
        expect(described_class.new(BaseService::Result.new, billing_items:, scope: :update)).to be_valid
        expect(described_class.new(BaseService::Result.new, billing_items:, scope: :approve)).to be_valid
      end
    end

    context "when billing_items is nil" do
      let(:billing_items) { nil }

      it "is valid at update scope" do
        expect(validator).to be_valid
        expect(result).to be_success
      end

      context "when the scope is approve" do
        let(:scope) { :approve }

        it "requires the plans list" do
          expect(validator).not_to be_valid
          expect(result.error.messages).to eq({"billing_items.plans": ["value_is_mandatory"]})
        end
      end
    end

    context "when billing_items is not an object" do
      let(:billing_items) { "bogus" }

      it "returns an invalid_type error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({billing_items: ["invalid_type"]})
      end
    end

    context "when billing_items contains an unknown root key" do
      let(:billing_items) { super().merge("addOns" => []) }

      it "returns an unsupported_key error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.addOns": ["unsupported_key"]})
      end
    end

    context "when the plan contains an unknown key" do
      let(:plan_item) { super().merge("entitlementsOverrides" => []) }

      it "returns an unsupported_key error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.entitlementsOverrides": ["unsupported_key"]})
      end
    end

    context "when the plan identity is missing" do
      let(:plan_item) { super().except("id", "localId") }

      it "requires id and localId at update scope" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {
            "billing_items.plans.0.id": ["value_is_mandatory"],
            "billing_items.plans.0.localId": ["value_is_mandatory"]
          }
        )
      end
    end

    context "when the plan id is not a uuid" do
      let(:plan_item) { super().merge("id" => "not-a-uuid") }

      it "returns an invalid_format error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.id": ["invalid_format"]})
      end
    end

    context "when the plan localId is empty" do
      let(:plan_item) { super().merge("localId" => "") }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.localId": ["invalid_value"]})
      end
    end

    context "when the plan type is not plan" do
      let(:plan_item) { super().merge("type" => "add_on") }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.type": ["invalid_value"]})
      end
    end

    context "when the plan type has a wrong JSON type" do
      let(:plan_item) { super().merge("type" => 123) }

      it "returns invalid_type and invalid_value errors" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.type": ["invalid_type", "invalid_value"]})
      end
    end

    context "when the plan payload is missing" do
      let(:plan_item) { super().except("payload") }

      it "returns a value_is_mandatory error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.payload": ["value_is_mandatory"]})
      end
    end

    context "when the plan payload is not an object" do
      let(:plan_payload) { "bogus" }

      it "returns an invalid_type error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.payload": ["invalid_type"]})
      end
    end

    context "when the plan payload contains unknown keys" do
      let(:plan_payload) { super().merge("customField" => {"nested" => true}) }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when the plan payload code is empty" do
      let(:plan_payload) { super().merge("code" => "") }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.payload.code": ["invalid_value"]})
      end
    end

    context "when the plan overrides contains an unknown key" do
      let(:plan_overrides) { super().merge("taxCodes" => ["vat_20"]) }

      it "returns an unsupported_key error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.overrides.taxCodes": ["unsupported_key"]})
      end
    end

    context "when the plan overrides amountCents is negative" do
      let(:plan_overrides) { super().merge("amountCents" => -1) }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.overrides.amountCents": ["invalid_value"]})
      end
    end

    context "when the plan overrides amountCents is fractional" do
      let(:plan_overrides) { super().merge("amountCents" => 10.5) }

      it "returns an invalid_type error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.overrides.amountCents": ["invalid_type"]})
      end
    end

    context "when the plan overrides charges is not an array" do
      let(:plan_overrides) { super().merge("charges" => {}) }

      it "returns an invalid_type error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.overrides.charges": ["invalid_type"]})
      end
    end

    context "when the charge override id is missing" do
      let(:charge_override) { super().except("id") }

      it "returns a value_is_mandatory error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.overrides.charges.0.id": ["value_is_mandatory"]})
      end
    end

    context "when the charge override id is not a uuid" do
      let(:charge_override) { super().merge("id" => "not-a-uuid") }

      it "returns an invalid_format error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.overrides.charges.0.id": ["invalid_format"]})
      end
    end

    context "when the charge override contains an unknown key" do
      let(:charge_override) { super().merge("chargeModel" => "standard") }

      it "returns an unsupported_key error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.overrides.charges.0.chargeModel": ["unsupported_key"]})
      end
    end

    context "when the charge override minAmountCents is negative" do
      let(:charge_override) { super().merge("minAmountCents" => -1) }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.overrides.charges.0.minAmountCents": ["invalid_value"]})
      end
    end

    context "when the charge override properties has model-specific keys" do
      let(:charge_override) do
        super().merge("properties" => {"graduatedRanges" => [{"fromValue" => 0, "toValue" => nil}]})
      end

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when the charge override properties is not an object" do
      let(:charge_override) { super().merge("properties" => "bogus") }

      it "returns an invalid_type error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.overrides.charges.0.properties": ["invalid_type"]})
      end
    end

    context "when the fixed charge override id is missing" do
      let(:fixed_charge_override) { super().except("id") }

      it "returns a value_is_mandatory error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.overrides.fixedCharges.0.id": ["value_is_mandatory"]})
      end
    end

    context "when the fixed charge override units is a number" do
      let(:fixed_charge_override) { super().merge("units" => 3) }

      it "returns an invalid_type error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.overrides.fixedCharges.0.units": ["invalid_type"]})
      end
    end

    context "when the fixed charge override units is empty" do
      let(:fixed_charge_override) { super().merge("units" => "") }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.overrides.fixedCharges.0.units": ["invalid_value"]})
      end
    end

    context "when the fixed charge override contains an unknown key" do
      let(:fixed_charge_override) { super().merge("applyUnitsImmediately" => true) }

      it "returns an unsupported_key error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.plans.0.overrides.fixedCharges.0.applyUnitsImmediately": ["unsupported_key"]}
        )
      end
    end

    context "when the coupon type is not coupon" do
      let(:coupon_item) { super().merge("type" => "plan") }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.coupons.0.type": ["invalid_value"]})
      end
    end

    context "when the coupon identity is missing" do
      let(:coupon_item) { super().except("id", "localId") }

      it "requires id and localId at update scope" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {
            "billing_items.coupons.0.id": ["value_is_mandatory"],
            "billing_items.coupons.0.localId": ["value_is_mandatory"]
          }
        )
      end
    end

    context "when the coupon payload contains unknown keys" do
      let(:coupon_payload) { super().merge("customField" => true) }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when the couponType is not in the enum" do
      let(:coupon_payload) { super().merge("couponType" => "bogus") }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.coupons.0.payload.couponType": ["invalid_value"]})
      end
    end

    context "when the couponType has a wrong JSON type" do
      let(:coupon_payload) { super().merge("couponType" => 123) }

      it "returns invalid_type and invalid_value errors" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.coupons.0.payload.couponType": ["invalid_type", "invalid_value"]}
        )
      end
    end

    context "when the coupon amountCents is negative" do
      let(:coupon_payload) { super().merge("amountCents" => -1) }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.coupons.0.payload.amountCents": ["invalid_value"]})
      end
    end

    context "when the coupon percentageRate is a string" do
      let(:coupon_payload) { super().merge("couponType" => "percentage", "percentageRate" => "10.0") }

      it "returns an invalid_type error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.coupons.0.payload.percentageRate": ["invalid_type"]})
      end
    end

    context "when the coupon percentageRate is zero" do
      let(:coupon_payload) { super().merge("couponType" => "percentage", "percentageRate" => 0) }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.coupons.0.payload.percentageRate": ["invalid_value"]})
      end
    end

    context "when the coupon frequency is not in the enum" do
      let(:coupon_payload) { super().merge("frequency" => "daily") }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.coupons.0.payload.frequency": ["invalid_value"]})
      end
    end

    context "when the coupon frequencyDuration is zero" do
      let(:coupon_payload) { super().merge("frequency" => "recurring", "frequencyDuration" => 0) }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.coupons.0.payload.frequencyDuration": ["invalid_value"]})
      end
    end

    context "when the wallet contains an id" do
      let(:wallet_item) { super().merge("id" => "48e59220-6722-49c1-8cdf-eacd040e2a56") }

      it "returns an unsupported_key error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.wallets.0.id": ["unsupported_key"]})
      end
    end

    context "when the wallet identity is missing" do
      let(:wallet_item) { super().except("localId", "payload") }

      it "requires localId and payload at update scope" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {
            "billing_items.wallets.0.localId": ["value_is_mandatory"],
            "billing_items.wallets.0.payload": ["value_is_mandatory"]
          }
        )
      end
    end

    context "when the wallet paidCredits is a number" do
      let(:wallet_payload) { super().merge("paidCredits" => 100) }

      it "returns an invalid_type error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.wallets.0.payload.paidCredits": ["invalid_type"]})
      end
    end

    context "when the wallet payload contains unknown keys" do
      let(:wallet_payload) { super().merge("name" => "Prepaid credits") }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when the recurring rule contains an unknown key" do
      let(:recurring_rule) { super().merge("startedAt" => "2026-01-01") }

      it "returns an unsupported_key error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.wallets.0.payload.recurringTransactionRules.0.startedAt": ["unsupported_key"]}
        )
      end
    end

    context "when the recurring rule trigger is not in the enum" do
      let(:recurring_rule) { super().merge("trigger" => "bogus") }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.wallets.0.payload.recurringTransactionRules.0.trigger": ["invalid_value"]}
        )
      end
    end

    context "when the recurring rule interval is not in the enum" do
      let(:recurring_rule) { super().merge("interval" => "daily") }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.wallets.0.payload.recurringTransactionRules.0.interval": ["invalid_value"]}
        )
      end
    end

    context "when the recurring rule method is not in the enum" do
      let(:recurring_rule) { super().merge("method" => "bogus") }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.wallets.0.payload.recurringTransactionRules.0.method": ["invalid_value"]}
        )
      end
    end

    context "when the recurring rule thresholdCredits is a number" do
      let(:recurring_rule) { super().merge("trigger" => "threshold", "thresholdCredits" => 100) }

      it "returns an invalid_type error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.wallets.0.payload.recurringTransactionRules.0.thresholdCredits": ["invalid_type"]}
        )
      end
    end

    context "when the scope is approve" do
      let(:scope) { :approve }

      context "when the plans list is empty" do
        let(:billing_items) { super().merge("plans" => []) }

        it "returns an invalid_count error" do
          expect(validator).not_to be_valid
          expect(result.error.messages).to eq({"billing_items.plans": ["invalid_count"]})
        end
      end

      context "when the plan payload is incomplete" do
        let(:plan_payload) { {"customField" => true} }

        it "requires the snapshot fields" do
          expect(validator).not_to be_valid
          expect(result.error.messages).to eq({"billing_items.plans.0.payload.code": ["value_is_mandatory"]})
        end
      end

      context "when the coupon payload is incomplete" do
        let(:coupon_payload) { {"amountCents" => 20_000} }

        it "requires the snapshot fields" do
          expect(validator).not_to be_valid
          expect(result.error.messages).to eq(
            {
              "billing_items.coupons.0.payload.code": ["value_is_mandatory"],
              "billing_items.coupons.0.payload.couponType": ["value_is_mandatory"]
            }
          )
        end
      end

      context "when the wallet payload is incomplete" do
        let(:wallet_payload) { {} }

        it "requires the snapshot fields" do
          expect(validator).not_to be_valid
          expect(result.error.messages).to eq(
            {
              "billing_items.wallets.0.payload.paidCredits": ["value_is_mandatory"],
              "billing_items.wallets.0.payload.grantedCredits": ["value_is_mandatory"],
              "billing_items.wallets.0.payload.rateAmount": ["value_is_mandatory"]
            }
          )
        end
      end
    end

    context "when the payloads are incomplete at update scope" do
      let(:plan_payload) { {} }
      let(:coupon_payload) { {} }
      let(:wallet_payload) { {} }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "with errors on multiple plans" do
      let(:billing_items) do
        super().merge(
          "plans" => [
            plan_item.merge("id" => "not-a-uuid"),
            plan_item.merge("payload" => plan_payload.merge("code" => ""))
          ]
        )
      end

      it "keys each error with the plan index" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {
            "billing_items.plans.0.id": ["invalid_format"],
            "billing_items.plans.1.payload.code": ["invalid_value"]
          }
        )
      end
    end

    context "with errors across item types" do
      let(:plan_item) { super().merge("id" => "not-a-uuid") }
      let(:coupon_payload) { super().merge("couponType" => "bogus") }
      let(:wallet_payload) { super().merge("rateAmount" => 1) }

      it "keys each error with its item type and index" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {
            "billing_items.plans.0.id": ["invalid_format"],
            "billing_items.coupons.0.payload.couponType": ["invalid_value"],
            "billing_items.wallets.0.payload.rateAmount": ["invalid_type"]
          }
        )
      end
    end
  end
end
