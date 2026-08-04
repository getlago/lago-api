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
  let(:billable_metric) { create(:billable_metric, organization:, code: "api_calls") }
  let(:charge) { create(:standard_charge, plan:, billable_metric:) }
  let(:fixed_charge) { create(:fixed_charge, plan:) }
  let(:coupon) { create(:coupon, organization:) }
  let(:scope) { :update }

  let(:plan_item) do
    {
      "id" => plan.id,
      "type" => "plan",
      "payload" => plan_payload,
      "overrides" => plan_overrides
    }
  end
  let(:plan_payload) do
    {
      "code" => plan.code,
      "charges" => [charge_snapshot],
      "fixedCharges" => [fixed_charge_snapshot]
    }
  end
  let(:charge_snapshot) do
    {
      "id" => charge.id,
      "billableMetric" => {"code" => billable_metric.code},
      "chargeModel" => charge.charge_model
    }
  end
  let(:fixed_charge_snapshot) do
    {
      "id" => fixed_charge.id,
      "addOn" => {"code" => fixed_charge.add_on.code},
      "chargeModel" => fixed_charge.charge_model
    }
  end
  let(:plan_overrides) do
    {
      "amountCents" => 500_000,
      "charges" => [charge_override],
      "fixedCharges" => [fixed_charge_override]
    }
  end
  let(:charge_override) do
    {
      "billableMetricCode" => charge.billable_metric.code,
      "chargeModel" => charge.charge_model,
      "properties" => {"amount" => "100"}
    }
  end
  let(:fixed_charge_override) { {"addOnCode" => fixed_charge.add_on.code, "units" => "3"} }

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
      "type" => "fixed_amount",
      "amountCents" => 20_000
    }
  end

  let(:wallet_credit_item) do
    {
      "localId" => "d9169d94-b322-4d70-a2b1-9e6a58e3f74a",
      "payload" => wallet_credit_payload
    }
  end
  let(:wallet_credit_payload) do
    {
      "paidCredits" => "100.0",
      "grantedCredits" => "10.0",
      "rateAmount" => "1.0",
      "currency" => "EUR",
      "recurringTransactionRules" => [recurring_rule]
    }
  end
  let(:recurring_rule) { {"trigger" => "interval", "interval" => "monthly", "method" => "fixed"} }

  let(:billing_items) do
    {
      "plans" => [plan_item],
      "coupons" => [coupon_item],
      "walletCredits" => [wallet_credit_item]
    }
  end

  describe "#valid?" do
    context "with a valid quote version" do
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

        it "requires the start date" do
          expect(validator).not_to be_valid
          expect(result.error.messages).to eq({start_date: ["value_is_mandatory"]})
        end
      end
    end

    context "when the end date is missing" do
      let(:quote_version) do
        create(:quote_version, quote:, organization:, currency: "EUR", start_date: Date.parse("2026-01-01"))
      end

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

      it "returns an invalid_date_range error at update scope" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({start_date: ["invalid_date_range"]})
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
      let(:billable_metric) { create(:billable_metric, organization: plan.organization, code: "api_calls") }
      let(:fixed_charge) { create(:fixed_charge, plan:) }

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

    context "when the plan currency differs from the version currency" do
      let(:plan) { create(:plan, organization:, amount_currency: "USD") }

      it "returns a currencies_does_not_match error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.id": ["currencies_does_not_match"]})
      end
    end

    context "when the charge override references a metric with no charge on the plan" do
      let(:charge_override) { super().merge("billableMetricCode" => "unknown_metric") }

      it "returns a charge_not_found error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.plans.0.overrides.charges.0.billableMetricCode": ["charge_not_found"]}
        )
      end
    end

    context "when the charge override references another plan's charge" do
      let(:other_metric) { create(:billable_metric, organization:, code: "other_metric") }
      let(:charge_override) { super().merge("billableMetricCode" => "other_metric") }

      before { create(:standard_charge, plan: create(:plan, organization:), billable_metric: other_metric) }

      it "returns a charge_not_found error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.plans.0.overrides.charges.0.billableMetricCode": ["charge_not_found"]}
        )
      end
    end

    context "when the charge is discarded" do
      before { charge.discard! }

      it "returns a charge_not_found error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.plans.0.overrides.charges.0.billableMetricCode": ["charge_not_found"]}
        )
      end
    end

    context "when the plan has two charges on the overridden metric" do
      before { create(:standard_charge, plan:, billable_metric:) }

      let(:plan_payload) { super().merge("charges" => [charge_snapshot, charge_snapshot.merge("id" => plan.charges.last.id)]) }

      it "returns an ambiguous_charge_override error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.plans.0.overrides.charges.0.billableMetricCode": ["ambiguous_charge_override"]}
        )
      end
    end

    context "when the snapshot carries no charges" do
      let(:plan_payload) { super().except("charges") }

      it "returns a charge_not_found error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.plans.0.overrides.charges.0.billableMetricCode": ["charge_not_found"]}
        )
      end
    end

    context "when the snapshot charge belongs to another plan" do
      let(:other_charge) { create(:standard_charge, plan: create(:plan, organization:), billable_metric:) }
      let(:charge_snapshot) { super().merge("id" => other_charge.id) }

      it "returns a charge_not_found error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.plans.0.overrides.charges.0.billableMetricCode": ["charge_not_found"]}
        )
      end
    end

    context "when the override charge model differs from the charge" do
      let(:charge_override) { super().merge("chargeModel" => "graduated") }

      it "returns a cannot_override_charge_model error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.plans.0.overrides.charges.0.chargeModel": ["cannot_override_charge_model"]}
        )
      end
    end

    context "when the billable metric is discarded" do
      before do
        charge
        billable_metric.discard!
      end

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when the fixed charge override references an add-on with no fixed charge on the plan" do
      let(:fixed_charge_override) { super().merge("addOnCode" => "unknown_add_on") }

      it "returns a fixed_charge_not_found error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.plans.0.overrides.fixedCharges.0.addOnCode": ["fixed_charge_not_found"]}
        )
      end
    end

    context "when the fixed charge is discarded" do
      before { fixed_charge.discard! }

      it "returns a fixed_charge_not_found error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.plans.0.overrides.fixedCharges.0.addOnCode": ["fixed_charge_not_found"]}
        )
      end
    end

    context "when the plan has two fixed charges on the overridden add-on" do
      before { create(:fixed_charge, plan:, add_on: fixed_charge.add_on) }

      let(:plan_payload) do
        super().merge("fixedCharges" => [fixed_charge_snapshot, fixed_charge_snapshot.merge("id" => plan.fixed_charges.last.id)])
      end

      it "returns an ambiguous_fixed_charge_override error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.plans.0.overrides.fixedCharges.0.addOnCode": ["ambiguous_fixed_charge_override"]}
        )
      end
    end

    context "when the fixed charge override units is negative" do
      let(:fixed_charge_override) { super().merge("units" => "-1") }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.plans.0.overrides.fixedCharges.0.units": ["invalid_value"]}
        )
      end
    end

    context "when the fixed charge override units is not a decimal" do
      let(:fixed_charge_override) { super().merge("units" => "abc") }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.plans.0.overrides.fixedCharges.0.units": ["invalid_value"]}
        )
      end
    end

    context "when the fixed charge override units is zero" do
      let(:fixed_charge_override) { super().merge("units" => "0") }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when the fixed charge override carries no units" do
      let(:fixed_charge_override) { super().except("units") }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when the plan overrides is null" do
      let(:plan_overrides) { nil }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when the minimum commitment override carries no amount" do
      let(:plan_overrides) do
        super().merge("minimumCommitment" => {"invoiceDisplayName" => "Min commitment"})
      end

      it "is valid at update scope" do
        expect(validator).to be_valid
      end

      context "when the scope is approve" do
        let(:scope) { :approve }

        it "requires the amountCents" do
          expect(validator).not_to be_valid
          expect(result.error.messages).to eq(
            {"billing_items.plans.0.overrides.minimumCommitment.amountCents": ["value_is_mandatory"]}
          )
        end

        context "when the plan carries a minimum commitment" do
          before { create(:commitment, plan:) }

          it "is valid" do
            expect(validator).to be_valid
          end
        end
      end
    end

    context "when the minimum commitment override amount is null" do
      let(:plan_overrides) do
        super().merge("minimumCommitment" => {"amountCents" => nil, "invoiceDisplayName" => "Min commitment"})
      end
      let(:scope) { :approve }

      before { create(:commitment, plan:) }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when the plan payload dates are not ISO 8601" do
      let(:plan_payload) { super().merge("startDate" => "not-a-date") }

      it "returns an invalid_date error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.payload.startDate": ["invalid_date"]})
      end
    end

    context "when the plan payload endDate is before its startDate" do
      let(:plan_payload) do
        super().merge("startDate" => "2026-06-01T00:00:00Z", "endDate" => "2026-01-01T00:00:00Z")
      end

      it "returns an invalid_date_range error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.payload.startDate": ["invalid_date_range"]})
      end
    end

    context "when the plan payload dates are date-only" do
      let(:plan_payload) { super().merge("startDate" => "2026-01-01", "endDate" => "2026-12-31") }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when the plan payload payment method belongs to the customer" do
      let(:payment_method) { create(:payment_method, organization:, customer:) }
      let(:plan_payload) { super().merge("paymentMethodId" => payment_method.id) }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when the plan payload payment method belongs to another customer" do
      let(:payment_method) { create(:payment_method, organization:, customer: create(:customer, organization:)) }
      let(:plan_payload) { super().merge("paymentMethodId" => payment_method.id) }

      it "returns a payment_method_not_found error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.plans.0.payload.paymentMethodId": ["payment_method_not_found"]}
        )
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
          "type" => "percentage",
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
        let(:coupon_payload) { {"code" => coupon.code, "type" => "fixed_amount", "amountCents" => nil} }

        it "requires amountCents" do
          expect(validator).not_to be_valid
          expect(result.error.messages).to eq({"billing_items.coupons.0.payload.amountCents": ["value_is_mandatory"]})
        end
      end

      context "when a fixed_amount coupon carries its amountCents in the overrides" do
        let(:coupon_payload) { {"code" => coupon.code, "type" => "fixed_amount"} }
        let(:coupon_item) { super().merge("overrides" => {"amountCents" => 15_000}) }

        it "is valid" do
          expect(validator).to be_valid
        end
      end

      context "when a percentage coupon payload has no percentageRate" do
        let(:coupon) { create(:coupon, organization:, coupon_type: "percentage", percentage_rate: 10) }
        let(:coupon_payload) { {"code" => coupon.code, "type" => "percentage", "percentageRate" => nil} }

        it "requires percentageRate" do
          expect(validator).not_to be_valid
          expect(result.error.messages).to eq(
            {"billing_items.coupons.0.payload.percentageRate": ["value_is_mandatory"]}
          )
        end
      end

      context "when a percentage coupon carries its percentageRate in the overrides" do
        let(:coupon) { create(:coupon, organization:, coupon_type: "percentage", percentage_rate: 10) }
        let(:coupon_payload) { {"code" => coupon.code, "type" => "percentage"} }
        let(:coupon_item) { super().merge("overrides" => {"percentageRate" => 15.0}) }

        it "is valid" do
          expect(validator).to be_valid
        end
      end

      context "when the coupon was retyped since the snapshot was taken" do
        let(:coupon) { create(:coupon, organization:, coupon_type: "percentage", percentage_rate: 10) }

        it "returns a coupon_type_does_not_match error" do
          expect(validator).not_to be_valid
          expect(result.error.messages).to eq(
            {"billing_items.coupons.0.payload.type": ["coupon_type_does_not_match"]}
          )
        end
      end

      context "when the coupon is overridden to recurring without a duration" do
        let(:coupon_item) { super().merge("overrides" => {"frequency" => "recurring"}) }

        it "requires the frequencyDuration" do
          expect(validator).not_to be_valid
          expect(result.error.messages).to eq(
            {"billing_items.coupons.0.overrides.frequencyDuration": ["value_is_mandatory"]}
          )
        end
      end

      context "when the coupon is overridden to recurring with a duration" do
        let(:coupon_item) do
          super().merge("overrides" => {"frequency" => "recurring", "frequencyDuration" => 3})
        end

        it "is valid" do
          expect(validator).to be_valid
        end
      end

      context "when the coupon payload is recurring without a duration" do
        let(:coupon_payload) { super().merge("frequency" => "recurring") }

        it "requires the frequencyDuration" do
          expect(validator).not_to be_valid
          expect(result.error.messages).to eq(
            {"billing_items.coupons.0.payload.frequencyDuration": ["value_is_mandatory"]}
          )
        end
      end

      context "when an already recurring coupon is overridden to recurring without a duration" do
        let(:coupon) do
          create(:coupon, organization:, frequency: "recurring", frequency_duration: 3)
        end
        let(:coupon_item) { super().merge("overrides" => {"frequency" => "recurring"}) }

        it "is valid" do
          expect(validator).to be_valid
        end
      end

      context "when the coupon overrides only the duration" do
        let(:coupon_item) { super().merge("overrides" => {"frequencyDuration" => 3}) }

        it "is valid" do
          expect(validator).to be_valid
        end
      end
    end

    context "when the coupon payload is recurring without a duration at update scope" do
      let(:coupon_payload) { super().merge("frequency" => "recurring") }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when a fixed_amount coupon payload has no amountCents at update scope" do
      let(:coupon_payload) { {"code" => coupon.code, "type" => "fixed_amount"} }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when the wallet credit paidCredits is not a decimal" do
      let(:wallet_credit_payload) { super().merge("paidCredits" => "abc") }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.walletCredits.0.payload.paidCredits": ["invalid_value"]})
      end
    end

    context "when the wallet credit grantedCredits is negative" do
      let(:wallet_credit_payload) { super().merge("grantedCredits" => "-1") }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.walletCredits.0.payload.grantedCredits": ["invalid_value"]})
      end
    end

    context "when the wallet credit rateAmount is zero" do
      let(:wallet_credit_payload) { super().merge("rateAmount" => "0") }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.walletCredits.0.payload.rateAmount": ["invalid_value"]})
      end
    end

    context "when the recurring rule trigger is interval without an interval" do
      let(:recurring_rule) { {"trigger" => "interval", "interval" => nil, "method" => "fixed"} }

      it "requires the interval" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.walletCredits.0.payload.recurringTransactionRules.0.interval": ["value_is_mandatory"]}
        )
      end
    end

    context "when the recurring rule trigger is threshold without thresholdCredits" do
      let(:recurring_rule) { {"trigger" => "threshold", "thresholdCredits" => nil, "method" => "fixed"} }

      it "requires thresholdCredits" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.walletCredits.0.payload.recurringTransactionRules.0.thresholdCredits": ["value_is_mandatory"]}
        )
      end
    end

    context "when the recurring rule thresholdCredits is not a decimal" do
      let(:recurring_rule) { {"trigger" => "threshold", "method" => "fixed", "thresholdCredits" => "abc"} }

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.walletCredits.0.payload.recurringTransactionRules.0.thresholdCredits": ["invalid_value"]}
        )
      end
    end

    context "when the recurring rule method is target without targetOngoingBalance" do
      let(:recurring_rule) do
        {"trigger" => "interval", "interval" => "monthly", "method" => "target", "targetOngoingBalance" => nil}
      end

      it "requires targetOngoingBalance" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.walletCredits.0.payload.recurringTransactionRules.0.targetOngoingBalance": ["value_is_mandatory"]}
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
          {"billing_items.walletCredits.0.payload.recurringTransactionRules.0.targetOngoingBalance": ["invalid_value"]}
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
          {"billing_items.walletCredits.0.payload.recurringTransactionRules.0.targetOngoingBalance": ["invalid_value"]}
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
          {"billing_items.walletCredits.0.payload.recurringTransactionRules.0.paidCredits": ["invalid_value"]}
        )
      end
    end

    context "when the wallet credit currency differs from the version currency" do
      let(:wallet_credit_payload) { super().merge("currency" => "USD") }

      it "returns a currencies_does_not_match error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.walletCredits.0.payload.currency": ["currencies_does_not_match"]}
        )
      end
    end

    context "when the wallet credit limits itself to a known billable metric" do
      let(:wallet_credit_payload) do
        super().merge("appliesTo" => {"feeTypes" => ["charge"], "billableMetricCodes" => [billable_metric.code]})
      end

      before { billable_metric }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when the wallet credit limits itself to an unknown billable metric" do
      let(:wallet_credit_payload) do
        super().merge("appliesTo" => {"billableMetricCodes" => ["unknown_metric"]})
      end

      it "returns a billable_metric_not_found error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.walletCredits.0.payload.appliesTo.billableMetricCodes": ["billable_metric_not_found"]}
        )
      end
    end

    context "when the wallet credit carries no currency" do
      let(:wallet_credit_payload) { super().except("currency") }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when the recurring rule grants a target top-up without the target method" do
      let(:recurring_rule) do
        {"trigger" => "interval", "interval" => "monthly", "method" => "fixed", "grantsTargetTopUp" => true}
      end

      it "returns an invalid_value error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.walletCredits.0.payload.recurringTransactionRules.0.grantsTargetTopUp": ["invalid_value"]}
        )
      end
    end

    context "when the recurring rule grants a target top-up with the target method" do
      let(:recurring_rule) do
        {
          "trigger" => "interval",
          "interval" => "monthly",
          "method" => "target",
          "targetOngoingBalance" => "500",
          "grantsTargetTopUp" => true
        }
      end

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when the recurring rule expirationAt is in the past" do
      let(:recurring_rule) { super().merge("expirationAt" => 1.day.ago.iso8601) }

      it "is valid at update scope" do
        expect(validator).to be_valid
      end

      context "when the scope is approve" do
        let(:scope) { :approve }

        it "returns an invalid_date error" do
          expect(validator).not_to be_valid
          expect(result.error.messages).to eq(
            {"billing_items.walletCredits.0.payload.recurringTransactionRules.0.expirationAt": ["invalid_date"]}
          )
        end
      end
    end

    context "when the wallet credit expirationAt is in the past" do
      let(:wallet_credit_payload) { super().merge("expirationAt" => 1.day.ago.iso8601) }
      let(:scope) { :approve }

      it "returns an invalid_date error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.walletCredits.0.payload.expirationAt": ["invalid_date"]}
        )
      end
    end

    context "when the wallet credit expirationAt is in the future" do
      let(:wallet_credit_payload) { super().merge("expirationAt" => 1.year.from_now.iso8601) }
      let(:scope) { :approve }

      it "is valid" do
        expect(validator).to be_valid
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
