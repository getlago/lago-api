# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::PlansController do
  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }

  describe "POST /api/v2/plans" do
    subject { post_with_token(organization, "/api/v2/plans", {plan: create_params}) }

    let(:create_params) { {name: "Growth", code: "growth", currency: "USD"} }

    include_examples "requires API permission", "plan", "write"

    it "creates a catalog plan" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:plan][:code]).to eq("growth")
      expect(json[:plan][:currency]).to eq("USD")
      expect(json[:plan]).not_to have_key(:interval)
      expect(json[:plan]).not_to have_key(:amount_cents)
      expect(CatalogPlan.find(json[:plan][:lago_id])).to be_present
    end

    context "when the payload is invalid" do
      let(:create_params) { {name: "Growth", code: "growth", currency: "INVALID"} }

      it "returns the validation error on the currency field" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json[:error_details][:currency]).to be_present
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

  describe "PUT /api/v2/plans/:code" do
    subject { put_with_token(organization, "/api/v2/plans/#{catalog_plan.code}", {plan: {name: "After"}}) }

    let(:catalog_plan) { create(:catalog_plan, organization:) }

    include_examples "requires API permission", "plan", "write"

    it "updates the plan" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:plan][:name]).to eq("After")
    end

    context "when the plan does not exist" do
      subject { put_with_token(organization, "/api/v2/plans/unknown", {plan: {name: "After"}}) }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("plan")
      end
    end
  end

  describe "GET /api/v2/plans/:code" do
    subject { get_with_token(organization, "/api/v2/plans/#{catalog_plan.code}") }

    let(:catalog_plan) { create(:catalog_plan, organization:) }

    include_examples "requires API permission", "plan", "read"

    it "returns the catalog plan shape" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:plan][:lago_id]).to eq(catalog_plan.id)
      expect(json[:plan][:applied_rate_cards_count]).to eq(0)
      expect(json[:plan]).not_to have_key(:interval)
    end

    context "when the plan does not exist" do
      subject { get_with_token(organization, "/api/v2/plans/unknown") }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("plan")
      end
    end
  end

  describe "GET /api/v2/plans" do
    subject { get_with_token(organization, "/api/v2/plans", params) }

    let(:params) { {} }
    let!(:catalog_plan) { create(:catalog_plan, organization:) }

    include_examples "requires API permission", "plan", "read"

    it "lists the organization catalog plans" do
      create(:catalog_plan)

      subject

      expect(response).to have_http_status(:success)
      expect(json[:plans].map { it[:lago_id] }).to eq([catalog_plan.id])
      expect(json[:plans].first[:currency]).to eq(catalog_plan.currency)
      expect(json[:plans].first).not_to have_key(:interval)
      expect(json[:meta][:total_count]).to eq(1)
    end

    context "with pagination" do
      let(:params) { {page: 2, per_page: 1} }

      before { create(:catalog_plan, organization:, code: "second") }

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
