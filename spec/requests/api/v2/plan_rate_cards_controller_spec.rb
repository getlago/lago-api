# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::PlanRateCardsController do
  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:rate_card) { create(:rate_card, organization:) }

  describe "POST /api/v2/plans/:plan_code/rate_cards" do
    subject { post_with_token(organization, "/api/v2/plans/#{plan_code}/rate_cards", {plan_rate_card: create_params}) }

    let(:plan_code) { plan.code }
    let(:create_params) do
      {rate_card_code: rate_card.code, units: "10"}
    end

    include_examples "requires API permission", "plan_rate_card", "write"

    it "assigns the rate card to the plan with a default rate phase" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:plan_rate_card][:lago_id]).to be_present
      expect(json[:plan_rate_card][:plan_code]).to eq(plan.code)
      expect(json[:plan_rate_card][:rate_card_code]).to eq(rate_card.code)
      expect(json[:plan_rate_card][:rate_phases_count]).to eq(1)
    end

    context "when the plan does not exist" do
      let(:plan_code) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("plan")
      end
    end

    context "when the rate card does not exist" do
      let(:create_params) { {rate_card_code: "unknown"} }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("rate_card")
      end
    end
  end

  describe "GET /api/v2/plans/:plan_code/rate_cards" do
    subject { get_with_token(organization, "/api/v2/plans/#{plan_code}/rate_cards") }

    let(:plan_code) { plan.code }
    let!(:plan_rate_card) { create(:plan_rate_card, organization:, plan:) }

    before { create(:plan_rate_card, organization:) }

    include_examples "requires API permission", "plan_rate_card", "read"

    it "returns the plan's entries only" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:plan_rate_cards].map { |i| i[:lago_id] }).to eq([plan_rate_card.id])
    end

    context "when the plan does not exist" do
      let(:plan_code) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("plan")
      end
    end
  end

  describe "GET /api/v2/plan_rate_cards/:id" do
    subject { get_with_token(organization, "/api/v2/plans/#{plan.code}/rate_cards/#{plan_rate_card.rate_card.code}") }

    let(:plan_rate_card) { create(:plan_rate_card, organization:, plan:) }

    include_examples "requires API permission", "plan_rate_card", "read"

    it "returns the plan product item" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:plan_rate_card][:lago_id]).to eq(plan_rate_card.id)
    end

    context "when it does not exist" do
      subject { get_with_token(organization, "/api/v2/plans/#{plan.code}/rate_cards/unknown") }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("plan_rate_card")
      end
    end
  end

  describe "PUT /api/v2/plan_rate_cards/:id" do
    subject { put_with_token(organization, "/api/v2/plans/#{plan.code}/rate_cards/#{plan_rate_card.rate_card.code}", {plan_rate_card: {units: "12"}}) }

    let(:plan_rate_card) { create(:plan_rate_card, organization:, plan:, units: 5) }

    include_examples "requires API permission", "plan_rate_card", "write"

    it "updates the entry" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:plan_rate_card][:units]).to eq("12.0")
    end

    context "when the plan has subscriptions" do
      before { create(:subscription, plan:, organization:) }

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "when it does not exist" do
      subject { put_with_token(organization, "/api/v2/plans/#{plan.code}/rate_cards/unknown", {plan_rate_card: {units: "12"}}) }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("plan_rate_card")
      end
    end
  end

  describe "DELETE /api/v2/plan_rate_cards/:id" do
    subject { delete_with_token(organization, "/api/v2/plans/#{plan.code}/rate_cards/#{plan_rate_card.rate_card.code}") }

    let(:plan_rate_card) { create(:plan_rate_card, organization:, plan:) }

    include_examples "requires API permission", "plan_rate_card", "write"

    it "soft deletes the entry" do
      subject

      expect(response).to have_http_status(:success)
      expect(plan.reload.plan_rate_cards).to be_empty
    end

    context "when the plan has subscriptions" do
      before { create(:subscription, plan:, organization:) }

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
