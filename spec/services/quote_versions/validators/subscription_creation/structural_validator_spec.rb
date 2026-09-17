# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuoteVersions::Validators::SubscriptionCreation::StructuralValidator do
  subject(:validator) { described_class.new(result, billing_items:, scope:) }

  let(:result) { BaseService::Result.new }
  let(:scope) { :update }

  let(:plan_item) do
    {
      "id" => "48e59220-6722-49c1-8cdf-eacd040e2a56",
      "type" => "plan",
      "payload" => plan_payload,
      "overrides" => plan_overrides
    }
  end
  let(:plan_payload) do
    {
      "code" => "base_plan",
      "name" => "Base Plan",
      "subscriptionExternalId" => "sub_ext_123",
      "subscriptionName" => "Main subscription",
      "billingTime" => "anniversary",
      "startDate" => "2026-01-01T00:00:00Z",
      "endDate" => "2026-12-31T00:00:00Z",
      "paymentMethodId" => "b1a1d0dc-3e2a-4e12-8f2a-16f0d5b7a0c1",
      "amountCents" => "10000",
      "charges" => [charge_snapshot],
      "fixedCharges" => [fixed_charge_snapshot]
    }
  end
  let(:charge_snapshot) do
    {
      "id" => "9c4681ce-b915-486a-9d94-a294d444a89b",
      "billableMetric" => {"code" => "api_calls", "name" => "API calls"},
      "chargeModel" => "standard"
    }
  end
  let(:fixed_charge_snapshot) do
    {
      "id" => "2f3a1b8c-5d6e-4f70-8a91-b2c3d4e5f607",
      "addOn" => {"code" => "seats", "name" => "Seats"},
      "chargeModel" => "standard"
    }
  end
  let(:plan_overrides) do
    {
      "amountCents" => 25_000,
      "invoiceDisplayName" => "Custom Enterprise fee",
      "charges" => [charge_override],
      "fixedCharges" => [fixed_charge_override],
      "minimumCommitment" => {"amountCents" => 50_000, "invoiceDisplayName" => "Min commitment"},
      "usageThresholds" => [
        {"amountCents" => 100_000, "recurring" => false, "thresholdDisplayName" => "First threshold"},
        {"amountCents" => 200_000, "recurring" => true, "thresholdDisplayName" => "Recurring cap"}
      ]
    }
  end
  let(:charge_override) do
    {
      "billableMetricCode" => "api_calls",
      "chargeModel" => "graduated",
      "properties" => {
        "graduatedRanges" => [
          {"fromValue" => 0, "toValue" => 1000, "perUnitAmount" => "0.005", "flatAmount" => "0"},
          {"fromValue" => 1001, "toValue" => nil, "perUnitAmount" => "0.002", "flatAmount" => "0"}
        ]
      },
      "minAmountCents" => 10_000,
      "invoiceDisplayName" => "API calls"
    }
  end
  let(:fixed_charge_override) do
    {
      "addOnCode" => "seats",
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
      "payload" => coupon_payload,
      "overrides" => coupon_overrides
    }
  end
  let(:coupon_payload) do
    {
      "code" => "SUMMER",
      "type" => "fixed_amount",
      "amountCents" => 5000,
      "percentageRate" => nil,
      "currency" => "USD",
      "frequency" => "once",
      "frequencyDuration" => nil,
      "expirationAt" => nil
    }
  end
  let(:coupon_overrides) do
    {
      "amountCents" => 9000,
      "percentageRate" => nil,
      "frequency" => "recurring",
      "frequencyDuration" => 3
    }
  end

  let(:wallet_credit_item) do
    {
      "localId" => "d9169d94-b322-4d70-a2b1-9e6a58e3f74a",
      "type" => "wallet_credit",
      "payload" => wallet_credit_payload
    }
  end
  let(:wallet_credit_payload) do
    {
      "name" => "Prepaid credits",
      "currency" => "USD",
      "rateAmount" => "1",
      "paidCredits" => "1000",
      "grantedCredits" => "200",
      "expirationAt" => nil,
      "purchaseOrderNumber" => "PO-123",
      "appliesTo" => {"feeTypes" => ["charge"], "billableMetricCodes" => ["api_calls"]},
      "recurringTransactionRules" => [recurring_rule]
    }
  end
  let(:recurring_rule) do
    {
      "trigger" => "interval",
      "method" => "target",
      "interval" => "monthly",
      "paidCredits" => "1000",
      "grantedCredits" => "200",
      "targetOngoingBalance" => "5000",
      "grantsTargetTopUp" => true,
      "thresholdCredits" => nil,
      "startedAt" => "2026-08-01T00:00:00Z",
      "transactionName" => "Monthly refill",
      "invoiceRequiresSuccessfulPayment" => false,
      "expirationAt" => nil
    }
  end

  let(:billing_items) do
    {
      "plans" => [plan_item],
      "coupons" => [coupon_item],
      "walletCredits" => [wallet_credit_item]
    }
  end

  describe "#valid?" do
    context "with a full valid payload" do
      it "is valid" do
        expect(validator).to be_valid
      end

      context "when the scope is approve" do
        let(:scope) { :approve }

        it "is valid" do
          expect(validator).to be_valid
        end
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

    context "when billing_items contains unknown root keys" do
      let(:billing_items) { super().merge("addOns" => [], "wallets" => []) }

      it "returns unsupported_key errors" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {
            "billing_items.addOns": ["unsupported_key"],
            "billing_items.wallets": ["unsupported_key"]
          }
        )
      end
    end

    context "when the plan contains an unknown key" do
      let(:plan_item) { super().merge("entitlementsOverrides" => []) }

      it "returns an unsupported_key error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.entitlementsOverrides": ["unsupported_key"]})
      end
    end

    context "when the plan localId is null" do
      let(:plan_item) { super().merge("localId" => nil) }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when the plan id is missing" do
      let(:plan_item) { super().except("id") }

      it "returns a value_is_mandatory error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.id": ["value_is_mandatory"]})
      end
    end

    context "when the plan id is not a uuid" do
      let(:plan_item) { super().merge("id" => "not-a-uuid") }

      it "returns an invalid_format error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.id": ["invalid_format"]})
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

    context "when the plan payload code is empty" do
      let(:plan_payload) { super().merge("code" => "") }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.payload.code": ["invalid_value"]})
      end
    end

    context "when the plan payload billingTime is not in the enum" do
      let(:plan_payload) { super().merge("billingTime" => "monthly") }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.payload.billingTime": ["invalid_value"]})
      end
    end

    context "when the plan payload paymentMethodId is not a uuid" do
      let(:plan_payload) { super().merge("paymentMethodId" => "not-a-uuid") }

      it "returns an invalid_format error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.payload.paymentMethodId": ["invalid_format"]})
      end
    end

    context "when the plan payload dates are date-only" do
      let(:plan_payload) { super().merge("startDate" => "2026-01-01", "endDate" => "2026-12-31") }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when a snapshot charge id is not a uuid" do
      let(:charge_snapshot) { super().merge("id" => "not-a-uuid") }

      it "returns an invalid_format error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.payload.charges.0.id": ["invalid_format"]})
      end
    end

    context "when a snapshot charge chargeModel is not in the enum" do
      let(:charge_snapshot) { super().merge("chargeModel" => "flat") }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.plans.0.payload.charges.0.chargeModel": ["invalid_value"]}
        )
      end
    end

    context "when a snapshot fixed charge chargeModel is not a fixed charge model" do
      let(:fixed_charge_snapshot) { super().merge("chargeModel" => "package") }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.plans.0.payload.fixedCharges.0.chargeModel": ["invalid_value"]}
        )
      end
    end

    context "when a snapshot charge carries no id" do
      let(:charge_snapshot) { super().except("id") }

      it "is valid at update scope" do
        expect(validator).to be_valid
      end

      context "when the scope is approve" do
        let(:scope) { :approve }

        it "requires the id the override is resolved through" do
          expect(validator).not_to be_valid
          expect(result.error.messages).to eq(
            {"billing_items.plans.0.payload.charges.0.id": ["value_is_mandatory"]}
          )
        end
      end
    end

    context "when a snapshot charge billable metric carries no code" do
      let(:charge_snapshot) { super().merge("billableMetric" => {"name" => "API calls"}) }

      it "is valid at update scope" do
        expect(validator).to be_valid
      end

      context "when the scope is approve" do
        let(:scope) { :approve }

        it "requires the code the override is matched on" do
          expect(validator).not_to be_valid
          expect(result.error.messages).to eq(
            {"billing_items.plans.0.payload.charges.0.billableMetric.code": ["value_is_mandatory"]}
          )
        end
      end
    end

    context "when a snapshot fixed charge carries no id" do
      let(:fixed_charge_snapshot) { super().except("id") }

      it "is valid at update scope" do
        expect(validator).to be_valid
      end

      context "when the scope is approve" do
        let(:scope) { :approve }

        it "requires the id the override is resolved through" do
          expect(validator).not_to be_valid
          expect(result.error.messages).to eq(
            {"billing_items.plans.0.payload.fixedCharges.0.id": ["value_is_mandatory"]}
          )
        end
      end
    end

    context "when a snapshot fixed charge add-on carries no code" do
      let(:fixed_charge_snapshot) { super().merge("addOn" => {"name" => "Seats"}) }

      it "is valid at update scope" do
        expect(validator).to be_valid
      end

      context "when the scope is approve" do
        let(:scope) { :approve }

        it "requires the code the override is matched on" do
          expect(validator).not_to be_valid
          expect(result.error.messages).to eq(
            {"billing_items.plans.0.payload.fixedCharges.0.addOn.code": ["value_is_mandatory"]}
          )
        end
      end
    end

    context "when the plan overrides is null" do
      let(:plan_overrides) { nil }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when the plan overrides contains an unknown key" do
      let(:plan_overrides) { super().merge("taxCodes" => ["vat_20"]) }

      it "returns an unsupported_key error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.overrides.taxCodes": ["unsupported_key"]})
      end
    end

    context "when the coupon overrides carries an amountCurrency" do
      let(:coupon_overrides) { super().merge("amountCurrency" => "EUR") }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when the coupon overrides amountCurrency is not a known currency" do
      let(:coupon_overrides) { super().merge("amountCurrency" => "DOUBLOON") }

      it "returns an invalid_currency error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.coupons.0.overrides.amountCurrency": ["invalid_currency"]})
      end
    end

    context "when the plan overrides carries an amountCurrency" do
      let(:plan_overrides) { super().merge("amountCurrency" => "EUR") }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when the plan overrides amountCurrency is not a known currency" do
      let(:plan_overrides) { super().merge("amountCurrency" => "DOUBLOON") }

      it "returns an invalid_currency error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.overrides.amountCurrency": ["invalid_currency"]})
      end
    end

    context "when the plan overrides amountCents is negative" do
      let(:plan_overrides) { super().merge("amountCents" => -1) }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.overrides.amountCents": ["invalid_value"]})
      end
    end

    context "when the plan overrides amountCents is null" do
      let(:plan_overrides) { super().merge("amountCents" => nil) }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when the plan overrides invoiceDisplayName is empty" do
      let(:plan_overrides) { super().merge("invoiceDisplayName" => "") }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.plans.0.overrides.invoiceDisplayName": ["invalid_value"]}
        )
      end
    end

    context "when the plan overrides carries trialPeriod, name and description" do
      let(:plan_overrides) do
        super().merge("trialPeriod" => 14.0, "name" => "Enterprise", "description" => "Negotiated wording")
      end

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when the plan overrides trialPeriod is negative" do
      let(:plan_overrides) { super().merge("trialPeriod" => -1) }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.overrides.trialPeriod": ["invalid_value"]})
      end
    end

    context "when the minimumCommitment contains an unknown key" do
      let(:plan_overrides) do
        super().merge("minimumCommitment" => {"amountCents" => 50_000, "taxCodes" => []})
      end

      it "returns an unsupported_key error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.plans.0.overrides.minimumCommitment.taxCodes": ["unsupported_key"]}
        )
      end
    end

    context "when the minimumCommitment amountCents is negative" do
      let(:plan_overrides) { super().merge("minimumCommitment" => {"amountCents" => -1}) }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.plans.0.overrides.minimumCommitment.amountCents": ["invalid_value"]}
        )
      end
    end

    context "when the minimumCommitment amountCents is zero" do
      let(:plan_overrides) { super().merge("minimumCommitment" => {"amountCents" => 0}) }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.plans.0.overrides.minimumCommitment.amountCents": ["invalid_value"]}
        )
      end
    end

    context "when the minimumCommitment carries only an invoiceDisplayName" do
      let(:plan_overrides) do
        super().merge("minimumCommitment" => {"invoiceDisplayName" => "Min commitment"})
      end

      it "is valid" do
        expect(validator).to be_valid
      end

      # The business validator decides whether the amount is mandatory, it can fall back to the
      # plan's own commitment.
      context "when the scope is approve" do
        let(:scope) { :approve }

        it "is valid" do
          expect(validator).to be_valid
        end
      end
    end

    context "when the minimumCommitment amountCents is null" do
      let(:plan_overrides) { super().merge("minimumCommitment" => {"amountCents" => nil}) }

      it "is valid" do
        expect(validator).to be_valid
      end

      context "when the scope is approve" do
        let(:scope) { :approve }

        it "is valid" do
          expect(validator).to be_valid
        end
      end
    end

    context "when the minimumCommitment is null" do
      let(:plan_overrides) { super().merge("minimumCommitment" => nil) }

      it "is valid" do
        expect(validator).to be_valid
      end

      context "when the scope is approve" do
        let(:scope) { :approve }

        it "is valid" do
          expect(validator).to be_valid
        end
      end
    end

    context "when a usage threshold has no amountCents" do
      let(:plan_overrides) { super().merge("usageThresholds" => [{"recurring" => true}]) }

      it "returns a value_is_mandatory error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.plans.0.overrides.usageThresholds.0.amountCents": ["value_is_mandatory"]}
        )
      end
    end

    context "when a usage threshold amountCents is zero" do
      let(:plan_overrides) { super().merge("usageThresholds" => [{"amountCents" => 0}]) }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.plans.0.overrides.usageThresholds.0.amountCents": ["invalid_value"]}
        )
      end
    end

    context "when a usage threshold recurring is not a boolean" do
      let(:plan_overrides) do
        super().merge("usageThresholds" => [{"amountCents" => 100, "recurring" => "yes"}])
      end

      it "returns an invalid_type error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.plans.0.overrides.usageThresholds.0.recurring": ["invalid_type"]}
        )
      end
    end

    context "when the charge override billableMetricCode is missing" do
      let(:charge_override) { super().except("billableMetricCode") }

      it "returns a value_is_mandatory error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.plans.0.overrides.charges.0.billableMetricCode": ["value_is_mandatory"]}
        )
      end
    end

    context "when the charge override contains an id" do
      let(:charge_override) { super().merge("id" => "9c4681ce-b915-486a-9d94-a294d444a89b") }

      it "returns an unsupported_key error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.overrides.charges.0.id": ["unsupported_key"]})
      end
    end

    context "when the charge override chargeModel is not in the enum" do
      let(:charge_override) { super().merge("chargeModel" => "flat") }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.plans.0.overrides.charges.0.chargeModel": ["invalid_value"]}
        )
      end
    end

    context "when the charge override chargeModel is null" do
      let(:charge_override) { super().merge("chargeModel" => nil) }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when the charge override properties is not an object" do
      let(:charge_override) { super().merge("properties" => "bogus") }

      it "returns an invalid_type error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.plans.0.overrides.charges.0.properties": ["invalid_type"]}
        )
      end
    end

    context "when the charge override minAmountCents is negative" do
      let(:charge_override) { super().merge("minAmountCents" => -1) }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.plans.0.overrides.charges.0.minAmountCents": ["invalid_value"]}
        )
      end
    end

    context "when the fixed charge override addOnCode is missing" do
      let(:fixed_charge_override) { super().except("addOnCode") }

      it "returns a value_is_mandatory error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.plans.0.overrides.fixedCharges.0.addOnCode": ["value_is_mandatory"]}
        )
      end
    end

    context "when the fixed charge override units is a number" do
      let(:fixed_charge_override) { super().merge("units" => 3) }

      it "returns an invalid_type error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.overrides.fixedCharges.0.units": ["invalid_type"]})
      end
    end

    context "when the fixed charge override units is null" do
      let(:fixed_charge_override) { super().merge("units" => nil) }

      it "is valid" do
        expect(validator).to be_valid
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
      let(:coupon_payload) { super().merge("catalogSnapshot" => nil, "planCodes" => []) }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when the coupon payload type is not in the enum" do
      let(:coupon_payload) { super().merge("type" => "bogus") }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.coupons.0.payload.type": ["invalid_value"]})
      end
    end

    context "when the coupon payload type has a wrong JSON type" do
      let(:coupon_payload) { super().merge("type" => 123) }

      it "returns invalid_type and invalid_value errors" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.coupons.0.payload.type": ["invalid_type", "invalid_value"]}
        )
      end
    end

    context "when the coupon payload currency is not a known currency" do
      let(:coupon_payload) { super().merge("currency" => "EURO") }

      it "returns an invalid_currency error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.coupons.0.payload.currency": ["invalid_currency"]})
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
      let(:coupon_payload) { super().merge("type" => "percentage", "percentageRate" => "10.0") }

      it "returns an invalid_type error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.coupons.0.payload.percentageRate": ["invalid_type"]})
      end
    end

    context "when the coupon percentageRate is zero" do
      let(:coupon_payload) { super().merge("type" => "percentage", "percentageRate" => 0) }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.coupons.0.payload.percentageRate": ["invalid_value"]})
      end
    end

    context "when the coupon frequencyDuration is zero" do
      let(:coupon_payload) { super().merge("frequency" => "recurring", "frequencyDuration" => 0) }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.coupons.0.payload.frequencyDuration": ["invalid_value"]})
      end
    end

    context "when the coupon overrides is null" do
      let(:coupon_overrides) { nil }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when the coupon overrides contains an unknown key" do
      let(:coupon_overrides) { super().merge("expirationAt" => nil) }

      it "returns an unsupported_key error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.coupons.0.overrides.expirationAt": ["unsupported_key"]})
      end
    end

    context "when the coupon overrides frequencyDuration is zero" do
      let(:coupon_overrides) { super().merge("frequencyDuration" => 0) }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.coupons.0.overrides.frequencyDuration": ["invalid_value"]}
        )
      end
    end

    context "when the wallet credit contains an id" do
      let(:wallet_credit_item) { super().merge("id" => "48e59220-6722-49c1-8cdf-eacd040e2a56") }

      it "returns an unsupported_key error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.walletCredits.0.id": ["unsupported_key"]})
      end
    end

    context "when the wallet credit type is wallet" do
      let(:wallet_credit_item) { super().merge("type" => "wallet") }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.walletCredits.0.type": ["invalid_value"]})
      end
    end

    context "when the wallet credit identity is missing" do
      let(:wallet_credit_item) { super().except("localId", "payload") }

      it "requires localId and payload at update scope" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {
            "billing_items.walletCredits.0.localId": ["value_is_mandatory"],
            "billing_items.walletCredits.0.payload": ["value_is_mandatory"]
          }
        )
      end
    end

    context "when the wallet credit paidCredits is a number" do
      let(:wallet_credit_payload) { super().merge("paidCredits" => 100) }

      it "returns an invalid_type error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.walletCredits.0.payload.paidCredits": ["invalid_type"]})
      end
    end

    context "when the wallet credit paidCredits is null" do
      let(:wallet_credit_payload) { super().merge("paidCredits" => nil) }

      it "is valid at update scope" do
        expect(validator).to be_valid
      end
    end

    context "when the wallet credit appliesTo carries an unknown fee type" do
      let(:wallet_credit_payload) do
        super().merge("appliesTo" => {"feeTypes" => ["bogus"], "billableMetricCodes" => []})
      end

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.walletCredits.0.payload.appliesTo.feeTypes.0": ["invalid_value"]}
        )
      end
    end

    context "when the wallet credit carries two recurring rules" do
      let(:wallet_credit_payload) { super().merge("recurringTransactionRules" => [recurring_rule, recurring_rule]) }

      it "is valid at update scope" do
        expect(validator).to be_valid
      end

      context "when the scope is approve" do
        let(:scope) { :approve }

        it "returns an invalid_count error" do
          expect(validator).not_to be_valid
          expect(result.error.messages).to eq(
            {"billing_items.walletCredits.0.payload.recurringTransactionRules": ["invalid_count"]}
          )
        end
      end
    end

    context "when the wallet credit currency is not a known currency" do
      let(:wallet_credit_payload) { super().merge("currency" => "EURO") }

      it "returns an invalid_currency error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.walletCredits.0.payload.currency": ["invalid_currency"]})
      end
    end

    context "when the wallet credit expirationAt is not an ISO 8601 date-time" do
      let(:wallet_credit_payload) { super().merge("expirationAt" => "not-a-date") }

      it "returns an invalid_format error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.walletCredits.0.payload.expirationAt": ["invalid_format"]})
      end
    end

    context "when the recurring rule contains an unknown key" do
      let(:recurring_rule) { super().merge("purchaseOrderNumber" => "PO-123") }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when the recurring rule grantsTargetTopUp is a string" do
      let(:recurring_rule) { super().merge("grantsTargetTopUp" => "true") }

      it "returns an invalid_type error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.walletCredits.0.payload.recurringTransactionRules.0.grantsTargetTopUp": ["invalid_type"]}
        )
      end
    end

    context "when the recurring rule trigger is null" do
      let(:recurring_rule) { super().merge("trigger" => nil) }

      it "is valid at update scope" do
        expect(validator).to be_valid
      end
    end

    context "when the recurring rule trigger is not in the enum" do
      let(:recurring_rule) { super().merge("trigger" => "bogus") }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.walletCredits.0.payload.recurringTransactionRules.0.trigger": ["invalid_value"]}
        )
      end
    end

    context "when the recurring rule interval is not in the enum" do
      let(:recurring_rule) { super().merge("interval" => "daily") }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.walletCredits.0.payload.recurringTransactionRules.0.interval": ["invalid_value"]}
        )
      end
    end

    context "when the recurring rule startedAt is not an ISO 8601 date-time" do
      let(:recurring_rule) { super().merge("startedAt" => "not-a-date") }

      it "returns an invalid_format error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.walletCredits.0.payload.recurringTransactionRules.0.startedAt": ["invalid_format"]}
        )
      end
    end

    context "when the recurring rule invoiceRequiresSuccessfulPayment is a string" do
      let(:recurring_rule) { super().merge("invoiceRequiresSuccessfulPayment" => "false") }

      it "returns an invalid_type error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.walletCredits.0.payload.recurringTransactionRules.0.invoiceRequiresSuccessfulPayment": ["invalid_type"]}
        )
      end
    end

    context "when the recurring rule thresholdCredits is a number" do
      let(:recurring_rule) { super().merge("thresholdCredits" => 100) }

      it "returns an invalid_type error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.walletCredits.0.payload.recurringTransactionRules.0.thresholdCredits": ["invalid_type"]}
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
        let(:plan_payload) { {"name" => "Base Plan"} }

        it "requires the snapshot fields" do
          expect(validator).not_to be_valid
          expect(result.error.messages).to eq({"billing_items.plans.0.payload.code": ["value_is_mandatory"]})
        end
      end

      context "when the coupon payload is incomplete" do
        let(:coupon_payload) { {"amountCents" => 5000} }

        it "requires the snapshot fields" do
          expect(validator).not_to be_valid
          expect(result.error.messages).to eq(
            {
              "billing_items.coupons.0.payload.code": ["value_is_mandatory"],
              "billing_items.coupons.0.payload.type": ["value_is_mandatory"]
            }
          )
        end
      end

      context "when the wallet credit payload is incomplete" do
        let(:wallet_credit_payload) { {} }

        it "requires the snapshot fields" do
          expect(validator).not_to be_valid
          expect(result.error.messages).to eq(
            {
              "billing_items.walletCredits.0.payload.paidCredits": ["value_is_mandatory"],
              "billing_items.walletCredits.0.payload.grantedCredits": ["value_is_mandatory"],
              "billing_items.walletCredits.0.payload.rateAmount": ["value_is_mandatory"]
            }
          )
        end
      end

      context "when the wallet credit paidCredits is null" do
        let(:wallet_credit_payload) { super().merge("paidCredits" => nil) }

        it "returns an invalid_type error" do
          expect(validator).not_to be_valid
          expect(result.error.messages).to eq({"billing_items.walletCredits.0.payload.paidCredits": ["invalid_type"]})
        end
      end

      context "when the recurring rule has no trigger" do
        let(:recurring_rule) { super().except("trigger") }

        it "requires the trigger" do
          expect(validator).not_to be_valid
          expect(result.error.messages).to eq(
            {"billing_items.walletCredits.0.payload.recurringTransactionRules.0.trigger": ["value_is_mandatory"]}
          )
        end
      end

      context "when the recurring rule trigger is null" do
        let(:recurring_rule) { super().merge("trigger" => nil) }

        it "returns invalid_type and invalid_value errors" do
          expect(validator).not_to be_valid
          expect(result.error.messages).to eq(
            {
              "billing_items.walletCredits.0.payload.recurringTransactionRules.0.trigger": [
                "invalid_type", "invalid_value"
              ]
            }
          )
        end
      end
    end

    context "when the payloads are incomplete at update scope" do
      let(:plan_payload) { {} }
      let(:coupon_payload) { {} }
      let(:wallet_credit_payload) { {} }

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
      let(:coupon_payload) { super().merge("type" => "bogus") }
      let(:wallet_credit_payload) { super().merge("rateAmount" => 1) }

      it "keys each error with its item type and index" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {
            "billing_items.plans.0.id": ["invalid_format"],
            "billing_items.coupons.0.payload.type": ["invalid_value"],
            "billing_items.walletCredits.0.payload.rateAmount": ["invalid_type"]
          }
        )
      end
    end
  end
end
