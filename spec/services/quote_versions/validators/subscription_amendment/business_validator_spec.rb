# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuoteVersions::Validators::SubscriptionAmendment::BusinessValidator do
  subject(:validator) { described_class.new(result, quote_version:, billing_items:, scope:) }

  let(:result) { BaseService::Result.new }
  let(:subscription) { create(:subscription, customer:, organization:, plan: target_plan) }
  let(:scope) { :approve }
  let(:quote) do
    create(:quote, organization:, customer:, subscription:, order_type: :subscription_amendment)
  end
  let(:quote_version) do
    create(:quote_version, quote:, organization:, currency: "EUR", billing_items:)
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

  let_it_be(:organization) { create(:organization) }
  let_it_be(:customer) { create(:customer, organization:) }
  let_it_be(:target_plan) { create(:plan, organization:, amount_cents: 10_000) }
  let_it_be(:plan) { create(:plan, organization:, amount_cents: 20_000) }

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

    # The replacement subscription then inherits the term of the one it amends.
    context "when the plan carries an ending date" do
      let(:plan_payload) { super().merge("endDate" => 1.year.from_now.iso8601) }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when the plan carries an ending date in the past" do
      let(:plan_payload) { super().merge("endDate" => 1.day.ago.iso8601) }

      it "refuses the amendment" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({"billing_items.plans.0.payload.endDate": ["invalid_date"]})
      end
    end

    # The amendment starts on the target's own anniversary date, so the quoted start date is a
    # commercial term the approval gate does not read.
    context "when the plan carries a start date that is not a date" do
      let(:plan_payload) { super().merge("startDate" => "whenever") }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when the plan ending date is before its start date" do
      let(:plan_payload) do
        super().merge("startDate" => 2.years.from_now.iso8601, "endDate" => 1.year.from_now.iso8601)
      end

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

    # The target is already bound to an entity and the plan change carries that binding over, so a
    # quoted entity could only move a running subscription to another numbering series.
    context "when the quote version names a billing entity" do
      let(:billing_entity) { create(:billing_entity, organization:) }
      let(:quote_version) do
        create(:quote_version, quote:, organization:, currency: "EUR", billing_items:, billing_entity:)
      end

      it "refuses the amendment" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({billing_entity_id: ["not_supported_for_order_type"]})
      end
    end

    context "when the quote carries no target subscription" do
      let(:quote) { build(:quote, organization:, customer:, order_type: :subscription_amendment) }
      let(:quote_version) do
        build(:quote_version, quote:, organization:, currency: "EUR", billing_items:)
      end

      it "refuses the amendment" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq({subscription_id: ["value_is_mandatory"]})
      end
    end

    # Execution schedules a reduction for the next billing day instead of applying it mid-period,
    # so the direction of the amendment is not the approval gate's business.
    context "when the amendment lowers the amount" do
      let(:plan) { create(:plan, organization:, amount_cents: 5_000) }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when an override lowers the amount below the target plan" do
      let(:plan_overrides) { {"amountCents" => 5_000} }

      it "is valid" do
        expect(validator).to be_valid
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
