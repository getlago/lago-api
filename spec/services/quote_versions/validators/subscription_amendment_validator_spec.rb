# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuoteVersions::Validators::SubscriptionAmendmentValidator do
  subject(:validator) { described_class.new(result, quote_version:, scope:) }

  let(:result) { BaseService::Result.new }
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:target_plan) { create(:plan, organization:, amount_cents: 10_000) }
  let(:subscription) { create(:subscription, customer:, organization:, plan: target_plan) }
  let(:plan) { create(:plan, organization:, amount_cents: 20_000) }
  let(:scope) { :approve }

  let(:quote) do
    create(:quote, organization:, customer:, subscription:, order_type: :subscription_amendment)
  end
  let(:quote_version) do
    create(
      :quote_version,
      quote:,
      organization:,
      currency: "EUR",
      billing_items:
    )
  end
  let(:plan_item) do
    {
      "id" => plan.id,
      "localId" => "3d08b2df-4e4c-4d58-b415-a525c1663735",
      "type" => "plan",
      "payload" => {"code" => plan.code}
    }
  end
  let(:billing_items) { {"plans" => [plan_item]} }

  describe "#valid?" do
    context "with a complete valid quote version" do
      it "is valid and leaves the result untouched" do
        expect(validator).to be_valid
        expect(result).to be_success
      end
    end

    context "with both structural and business errors" do
      let(:plan_item) { super().merge("overrides" => {"taxCodes" => ["vat_20"]}) }
      let(:subscription) { create(:subscription, :terminated, customer:, organization:, plan: target_plan) }

      it "returns the structural errors first" do
        expect(validator).not_to be_valid
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages).to eq({"billing_items.plans.0.overrides.taxCodes": ["unsupported_key"]})
      end
    end

    context "with a valid structure and an inactive target subscription" do
      let(:subscription) { create(:subscription, :terminated, customer:, organization:, plan: target_plan) }

      it "reports the business error" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({subscription_id: ["subscription_not_active"]})
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
