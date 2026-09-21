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

    context "with taxes" do
      let(:tax1) { create(:tax, organization:) }
      let(:tax2) { create(:tax, organization:) }
      let(:create_params) do
        {name: "Growth", code: "growth", currency: "USD", tax_codes: [tax1.code, tax2.code]}
      end

      it "assigns and returns the taxes" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:plan][:taxes].pluck(:code)).to match_array([tax1.code, tax2.code])
        expect(CatalogPlan.find(json[:plan][:lago_id]).taxes).to match_array([tax1, tax2])
      end
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

    context "with taxes" do
      subject do
        put_with_token(
          organization,
          "/api/v2/plans/#{catalog_plan.code}",
          {plan: {tax_codes: [tax.code]}}
        )
      end

      let(:tax) { create(:tax, organization:) }

      it "assigns and returns the taxes" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:plan][:taxes].pluck(:code)).to eq([tax.code])
        expect(catalog_plan.reload.taxes).to eq([tax])
      end
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

    it "returns the assigned taxes" do
      tax = create(:tax, organization:)
      create(:plan_applied_tax, :catalog_plan, catalog_plan:, tax:, organization:)

      subject

      expect(json[:plan][:taxes].pluck(:code)).to eq([tax.code])
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
      create_list(:plan_rate_card, 2, organization:, catalog_plan:)

      subject

      expect(response).to have_http_status(:success)
      expect(json[:plans].map { it[:lago_id] }).to eq([catalog_plan.id])
      expect(json[:plans].first[:currency]).to eq(catalog_plan.currency)
      expect(json[:plans].first[:applied_rate_cards_count]).to eq(2)
      expect(json[:plans].first).not_to have_key(:interval)
      expect(json[:meta][:total_count]).to eq(1)
    end

    it "returns the assigned taxes" do
      tax = create(:tax, organization:)
      create(:plan_applied_tax, :catalog_plan, catalog_plan:, tax:, organization:)

      subject

      expect(json[:plans].first[:taxes].pluck(:code)).to eq([tax.code])
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

  # A plan created through this surface is a CatalogPlan, and the nested
  # applied_rate_cards routes resolve their parent from catalog_plans too, so
  # the create-then-attach flow works end to end.
  describe "attaching a rate card to a catalog plan" do
    let(:rate_card) { create(:rate_card, organization:, currency: "USD") }

    it "attaches the rate card to the plan created here" do
      post_with_token(organization, "/api/v2/plans", {plan: {name: "Growth", code: "growth", currency: "USD"}})
      expect(response).to have_http_status(:success)

      post_with_token(
        organization,
        "/api/v2/plans/growth/applied_rate_cards",
        {applied_rate_card: {rate_card_code: rate_card.code}}
      )

      expect(response).to have_http_status(:success)
      expect(json[:applied_rate_card][:plan_code]).to eq("growth")
      expect(json[:applied_rate_card][:rate_card_code]).to eq(rate_card.code)
    end
  end
end
