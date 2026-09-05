# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuoteVersions::Validators::SubscriptionCreationValidator do
  subject(:validator) { described_class.new(result, quote_version:, scope:) }

  let(:result) { BaseService::Result.new }
  let(:quote) { create(:quote, organization:, customer:, order_type: :subscription_creation) }
  let(:quote_version) do
    create(
      :quote_version,
      quote:,
      organization:,
      currency: "EUR",
      billing_items:
    )
  end
  let(:coupon) { create(:coupon, organization:) }
  let(:scope) { :approve }
  let(:plan_item) do
    {
      "id" => plan.id,
      "localId" => "3d08b2df-4e4c-4d58-b415-a525c1663735",
      "type" => "plan",
      "payload" => {"code" => plan.code, "startDate" => "2026-01-01", "endDate" => "2026-12-31"}
    }
  end
  let(:coupon_item) do
    {
      "id" => coupon.id,
      "localId" => "ba54903c-7bd5-4d40-8d51-45a5157005ff",
      "type" => "coupon",
      "payload" => {"code" => coupon.code, "type" => "fixed_amount", "amountCents" => 20_000}
    }
  end
  let(:wallet_credit_item) do
    {
      "localId" => "d9169d94-b322-4d70-a2b1-9e6a58e3f74a",
      "type" => "wallet_credit",
      "payload" => {"paidCredits" => "100.0", "grantedCredits" => "10.0", "rateAmount" => "1.0"}
    }
  end
  let(:billing_items) do
    {
      "plans" => [plan_item],
      "coupons" => [coupon_item],
      "walletCredits" => [wallet_credit_item]
    }
  end

  let_it_be(:organization) { create(:organization) }
  let_it_be(:customer) { create(:customer, organization:) }
  let_it_be(:plan) { create(:plan, organization:) }

  describe "#valid?" do
    context "with a complete valid quote version" do
      it "is valid and leaves the result untouched" do
        expect(validator).to be_valid
        expect(result).to be_success
      end
    end

    context "with both structural and business errors" do
      let(:plan_item) { super().merge("overrides" => {"amountCents" => -1}) }
      let(:quote_version) do
        build(
          :quote_version,
          quote:,
          organization:,
          currency: "DOUBLOON",
          billing_items:
        )
      end

      it "returns the structural errors first" do
        expect(validator).not_to be_valid
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages).to eq({"billing_items.plans.0.overrides.amountCents": ["invalid_value"]})
      end
    end

    context "with a valid structure and an unknown plan" do
      let(:plan_item) { super().merge("id" => "11111111-2222-3333-4444-555555555555") }

      it "reports the business error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.id": ["plan_not_found"]})
      end
    end

    context "when the structure is invalid" do
      let(:plan_item) do
        super().merge("entitlementsOverrides" => [], "id" => "11111111-2222-3333-4444-555555555555")
      end

      it "returns only structural errors and skips business validation" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(
          {"billing_items.plans.0.entitlementsOverrides": ["unsupported_key"]}
        )
      end
    end

    context "when billing_items has symbol keys" do
      let(:billing_items) do
        {
          plans: [
            {
              id: plan.id,
              localId: "3d08b2df-4e4c-4d58-b415-a525c1663735",
              type: "plan",
              payload: {code: plan.code, startDate: "2026-01-01", endDate: "2026-12-31"}
            }
          ]
        }
      end

      it "normalizes them before validating" do
        expect(validator).to be_valid
      end
    end

    context "when billing_items is nil at update scope" do
      let(:scope) { :update }
      let(:billing_items) { nil }

      it "is valid" do
        expect(validator).to be_valid
        expect(result).to be_success
      end
    end
  end
end
