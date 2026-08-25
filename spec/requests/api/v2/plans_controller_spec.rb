# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::PlansController do
  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }

  describe "POST /api/v2/plans" do
    subject { post_with_token(organization, "/api/v2/plans", {plan: create_params}) }

    let(:create_params) { {name: "Growth", code: "growth", currency: "USD"} }

    include_examples "requires API permission", "plan", "write"

    it "creates a catalog plan without any legacy pricing field" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:plan][:code]).to eq("growth")
      expect(json[:plan][:currency]).to eq("USD")
      expect(json[:plan]).not_to have_key(:interval)
      expect(json[:plan]).not_to have_key(:amount_cents)
      expect(Plan.find(json[:plan][:lago_id])).to be_product_catalog
    end

    context "when the organization is not on the product catalog", product_catalog: false do
      let(:organization) { create(:organization) }

      it "returns a forbidden error" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
      end
    end
  end

  describe "PUT /api/v2/plans/:code" do
    subject { put_with_token(organization, "/api/v2/plans/#{plan.code}", {plan: {name: "After"}}) }

    let(:plan) { create(:plan, organization:, pricing_type: "product_catalog") }

    include_examples "requires API permission", "plan", "write"

    it "updates the plan" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:plan][:name]).to eq("After")
    end

    context "when changing the currency of a plan holding applied rate cards" do
      subject { put_with_token(organization, "/api/v2/plans/#{plan.code}", {plan: {currency: "USD"}}) }

      before { create(:plan_rate_card, organization:, plan:) }

      it "rejects the change on the v2 field name" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json[:error_details][:currency]).to eq(["not_editable_with_applied_rate_cards"])
      end
    end
  end

  describe "GET /api/v2/plans/:code" do
    subject { get_with_token(organization, "/api/v2/plans/#{plan.code}") }

    let(:plan) { create(:plan, organization:, pricing_type: "product_catalog") }

    include_examples "requires API permission", "plan", "read"

    it "returns the catalog plan shape" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:plan][:lago_id]).to eq(plan.id)
      expect(json[:plan][:applied_rate_cards_count]).to eq(0)
      expect(json[:plan]).not_to have_key(:interval)
    end
  end

  describe "GET /api/v2/plans" do
    subject { get_with_token(organization, "/api/v2/plans", params) }

    let(:params) { {} }
    let!(:plan) { create(:plan, organization:, pricing_type: "product_catalog") }

    include_examples "requires API permission", "plan", "read"

    it "lists catalog plans with the catalog shape" do
      create(:plan, organization:)
      create(:plan, pricing_type: "product_catalog")

      subject

      expect(response).to have_http_status(:success)
      expect(json[:plans].map { it[:lago_id] }).to eq([plan.id])
      expect(json[:plans].first[:currency]).to eq(plan.amount_currency)
      expect(json[:plans].first).not_to have_key(:interval)
      expect(json[:meta][:total_count]).to eq(1)
    end

    context "with pagination" do
      let(:params) { {page: 2, per_page: 1} }

      before { create(:plan, organization:, pricing_type: "product_catalog", code: "second") }

      it "paginates the catalog plans" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:plans].count).to eq(1)
        expect(json[:meta][:current_page]).to eq(2)
        expect(json[:meta][:total_count]).to eq(2)
      end
    end

    context "when the organization is not on the product catalog", product_catalog: false do
      let(:organization) { create(:organization) }

      it "returns a forbidden error" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
      end
    end
  end
end
