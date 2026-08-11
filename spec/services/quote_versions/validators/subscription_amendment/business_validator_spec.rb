# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuoteVersions::Validators::SubscriptionAmendment::BusinessValidator do
  subject(:validator) { described_class.new(result, quote_version:, billing_items:, scope:) }

  let(:result) { BaseService::Result.new }
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:target_plan) { create(:plan, organization:, amount_cents: 10_000) }
  let(:subscription) { create(:subscription, customer:, organization:, plan: target_plan) }
  let(:plan) { create(:plan, organization:, amount_cents: 20_000) }
  let(:scope) { :approve }
  let(:start_date) { Date.current }
  let(:end_date) { 1.year.from_now.to_date }

  let(:quote) do
    create(:quote, organization:, customer:, subscription:, order_type: :subscription_amendment)
  end
  let(:quote_version) do
    create(:quote_version, quote:, organization:, currency: "EUR", start_date:, end_date:, billing_items:)
  end
  let(:plan_payload) { {"code" => plan.code} }
  let(:plan_overrides) { nil }
  let(:plan_item) do
    {
      "id" => plan.id,
      "localId" => "3d08b2df-4e4c-4d58-b415-a525c1663735",
      "type" => "plan",
      "payload" => plan_payload,
      "overrides" => plan_overrides
    }.compact
  end
  let(:billing_items) { {"plans" => [plan_item]} }

  describe "#valid?" do
    it "is valid and leaves the result untouched" do
      expect(validator).to be_valid
      expect(result).to be_success
    end

    context "when the quote carries a second plan" do
      let(:billing_items) { {"plans" => [plan_item, plan_item]} }

      it "refuses the amendment" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans": ["single_plan_expected"]})
      end
    end

    context "when the quote carries a second plan at update scope" do
      let(:scope) { :update }
      let(:billing_items) { {"plans" => [plan_item, plan_item]} }

      it "refuses it too, so a draft never accumulates one" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans": ["single_plan_expected"]})
      end
    end

    context "when the ending date is missing" do
      let(:end_date) { nil }

      it "refuses the amendment" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({end_date: ["value_is_mandatory"]})
      end
    end

    context "when the ending date is missing at update scope" do
      let(:scope) { :update }
      let(:end_date) { nil }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when only the plan carries an ending date" do
      let(:end_date) { nil }
      let(:plan_payload) { super().merge("endDate" => 1.year.from_now.iso8601) }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when the target subscription is terminated" do
      let(:subscription) { create(:subscription, :terminated, customer:, organization:, plan: target_plan) }

      it "refuses the amendment" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({subscription_id: ["subscription_not_active"]})
      end
    end

    context "when the target subscription is pending" do
      let(:subscription) { create(:subscription, :pending, customer:, organization:, plan: target_plan) }

      it "refuses the amendment" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({subscription_id: ["subscription_not_active"]})
      end
    end

    context "when the quote carries no target subscription" do
      let(:quote) { build(:quote, organization:, customer:, order_type: :subscription_amendment) }
      let(:quote_version) do
        build(:quote_version, quote:, organization:, currency: "EUR", start_date:, end_date:, billing_items:)
      end

      it "refuses the amendment" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({subscription_id: ["value_is_mandatory"]})
      end
    end

    context "when the amendment lowers the amount" do
      let(:plan) { create(:plan, organization:, amount_cents: 5_000) }

      it "refuses the amendment" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.id": ["amendment_decreases_amount"]})
      end
    end

    context "when the amendment keeps the same amount" do
      let(:plan) { create(:plan, organization:, amount_cents: 10_000) }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when an override lowers the amount below the target plan" do
      let(:plan_overrides) { {"amountCents" => 5_000} }

      it "refuses the amendment" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.id": ["amendment_decreases_amount"]})
      end
    end

    context "when an override raises the amount above the target plan" do
      let(:plan) { create(:plan, organization:, amount_cents: 5_000) }
      let(:plan_overrides) { {"amountCents" => 20_000} }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when the intervals differ" do
      let(:target_plan) { create(:plan, organization:, interval: "yearly", amount_cents: 100_000) }
      let(:plan) { create(:plan, organization:, interval: "monthly", amount_cents: 10_000) }

      it "compares both on a yearly basis" do
        expect(validator).to be_valid
      end
    end

    context "when a monthly amendment is cheaper than the target on a yearly basis" do
      let(:target_plan) { create(:plan, organization:, interval: "yearly", amount_cents: 200_000) }
      let(:plan) { create(:plan, organization:, interval: "monthly", amount_cents: 10_000) }

      it "refuses the amendment" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.id": ["amendment_decreases_amount"]})
      end
    end

    context "when the plan is unknown" do
      let(:plan_item) { super().merge("id" => "11111111-2222-3333-4444-555555555555") }

      it "reports the inherited error and skips the direction check" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.id": ["plan_not_found"]})
      end
    end

    context "when the plan currency does not match the deal" do
      let(:plan) { create(:plan, organization:, amount_cents: 20_000, amount_currency: "USD") }

      it "still runs the inherited checks" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.id": ["currencies_does_not_match"]})
      end
    end
  end
end
