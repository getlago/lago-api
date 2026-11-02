# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::PlansController do
  let_it_be(:organization, refind: true) { create_default(:organization, feature_flags: ["product_catalog"]) }
  let(:plan_keys) { %i[lago_id name invoice_display_name code description currency created_at deleted_at] }

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

    context "with expand" do
      subject { post_with_token(organization, "/api/v2/plans?expands[]=taxes", {plan: create_params}) }

      it "creates nothing, as only show expands" do
        expect { subject }.not_to change(CatalogPlan, :count)

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("expand_not_supported")
        expect(json[:details]).to eq([{code: "action_not_expandable", field: "expands", meta: {invalid_values: %w[taxes]}}])
      end
    end

    context "with taxes" do
      let(:tax1) { create(:tax, organization:) }
      let(:tax2) { create(:tax, organization:) }
      let(:create_params) do
        {name: "Growth", code: "growth", currency: "USD", tax_codes: [tax1.code, tax2.code]}
      end

      it "assigns the taxes, which a show then expands" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:plan].keys).to eq(plan_keys)
        expect(CatalogPlan.find(json[:plan][:lago_id]).taxes).to match_array([tax1, tax2])

        get_with_token(organization, "/api/v2/plans/growth", {expands: %w[taxes]})

        expect(json[:plan][:taxes].pluck(:code)).to match_array([tax1.code, tax2.code])
      end
    end

    context "when the payload is invalid" do
      let(:create_params) { {name: "Growth", code: "growth", currency: "INVALID"} }

      it "returns the validation error on the currency field" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json[:details]).to eq([{code: "value_is_invalid", field: "currency", meta: {}}])
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

      it "assigns the taxes and returns the plan without them" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:plan].keys).to eq(plan_keys)
        expect(catalog_plan.reload.taxes).to eq([tax])
      end
    end

    context "when the plan does not exist" do
      subject { put_with_token(organization, "/api/v2/plans/unknown", {plan: {name: "After"}}) }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("plan")
      end
    end
  end

  describe "GET /api/v2/plans/:code" do
    subject { get_with_token(organization, "/api/v2/plans/#{catalog_plan.code}", params) }

    let(:catalog_plan) { create(:catalog_plan, organization:) }
    let(:params) { {} }
    let(:tax) { create(:tax, organization:) }
    let(:linked_at) { Time.current }
    let(:flat_payload) do
      {
        lago_id: catalog_plan.id,
        name: catalog_plan.name,
        invoice_display_name: catalog_plan.invoice_display_name,
        code: catalog_plan.code,
        description: catalog_plan.description,
        currency: catalog_plan.currency,
        created_at: catalog_plan.created_at.iso8601(6),
        deleted_at: nil
      }
    end

    before { create(:plan_applied_tax, :catalog_plan, catalog_plan:, tax:, organization:, created_at: linked_at) }

    include_examples "requires API permission", "plan", "read"

    it "returns the flat plan, without its taxes" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:plan]).to eq(flat_payload)
    end

    context "with expands[]=taxes" do
      let(:params) { {expands: %w[taxes]} }
      let(:created_at) { Time.zone.parse("2026-09-28T10:00:00.000001Z") }
      let(:tax) { create(:tax, organization:, created_at: created_at - 1.day) }
      let(:linked_at) { created_at - 1.second }
      # Two taxes created before `tax` but linked after it, at the same microsecond with ascending
      # ids, so that only the link order, then the id tiebreak, gives the list.
      let(:tied_links) do
        Array.new(2) { SecureRandom.uuid }.sort.map do |id|
          create(:plan_applied_tax, :catalog_plan, id:, catalog_plan:, organization:, tax: create(:tax, organization:, created_at: created_at - 2.days), created_at:)
        end
      end
      let(:discarded_tax) { create(:tax, organization:) }

      # Next to taxes that the plan may not show.
      before do
        tied_links
        create(:plan_applied_tax, :catalog_plan, catalog_plan:, tax: discarded_tax, organization:)
        # Discarded directly: Taxes::DestroyService would delete the link as well.
        discarded_tax.discard!
        create(:plan_applied_tax, :catalog_plan, catalog_plan: create(:catalog_plan, organization:), organization:)
      end

      def tax_payload(tax)
        {
          lago_id: tax.id,
          name: tax.name,
          code: tax.code,
          rate: tax.rate,
          description: tax.description,
          created_at: tax.created_at.iso8601(6),
          updated_at: tax.updated_at.iso8601(6),
          deleted_at: nil
        }
      end

      it "embeds its kept taxes, latest linked first" do
        subject

        listed = [*tied_links.reverse.map(&:tax), tax]

        expect(response).to have_http_status(:success)
        expect(json[:plan]).to eq(flat_payload.merge(taxes: listed.map { tax_payload(it) }))
      end
    end

    context "with an unknown expansion" do
      let(:params) { {expands: %w[taxes applied_rate_cards]} }

      it "returns an invalid expand error listing the allowed expansions" do
        subject

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("invalid_expand")
        expect(json[:details]).to eq([{code: "invalid_expand", field: "expands", meta: {invalid_values: %w[applied_rate_cards], allowed_values: %w[taxes]}}])
      end
    end

    context "when the plan does not exist" do
      subject { get_with_token(organization, "/api/v2/plans/unknown") }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("plan")
      end
    end
  end

  describe "GET /api/v2/plans" do
    subject { get_with_token(organization, "/api/v2/plans", params) }

    let(:params) { {} }
    let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
    let!(:catalog_plan) { create(:catalog_plan, organization:) }

    include_examples "requires API permission", "plan", "read"

    it "lists the organization catalog plans" do
      create(:catalog_plan)

      subject

      expect(response).to have_http_status(:success)
      expect(json[:plans].map { it[:lago_id] }).to eq([catalog_plan.id])
      expect(json[:plans].first[:currency]).to eq(catalog_plan.currency)
      expect(json[:plans].first.keys).to eq(plan_keys)
      expect(json[:meta]).to eq(next_cursor: nil, prev_cursor: nil)
    end

    context "with scoping params" do
      let(:rate_card) { create(:rate_card, organization:) }
      let(:params) { {rate_card_id: [rate_card.id]} }

      before do
        create(:catalog_plan, organization:)
        create(:plan_rate_card, organization:, catalog_plan:, rate_card:)
      end

      it "lists the plans holding those rate cards" do
        subject

        expect(json[:plans].map { it[:lago_id] }).to eq([catalog_plan.id])
      end
    end

    context "with a search term" do
      let(:params) { {search_term: catalog_plan.code} }

      before { create(:catalog_plan, organization:) }

      it "lists the plans matching it" do
        subject

        expect(json[:plans].map { it[:lago_id] }).to eq([catalog_plan.id])
      end
    end

    it "lists the plans without their taxes" do
      create(:plan_applied_tax, :catalog_plan, catalog_plan:, organization:)

      subject

      expect(json[:plans].sole.keys).to eq(plan_keys)
    end

    context "with expands[]=taxes" do
      let(:params) { {expands: %w[taxes]} }

      it "returns an expand error, as only show expands" do
        subject

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("expand_not_supported")
        expect(json[:details]).to eq([{code: "action_not_expandable", field: "expands", meta: {invalid_values: %w[taxes]}}])
      end
    end

    it_behaves_like "a cursor paginated v2 endpoint", collection: :plans, model: CatalogPlan do
      let(:paginated_path) { "/api/v2/plans" }
      let(:create_paginated_record) { ->(created_at) { create(:catalog_plan, organization:, created_at:) } }
    end

    it_behaves_like "a v2 list filtered on created_at", collection: :plans do
      let(:filtered_path) { "/api/v2/plans" }
      let(:create_filtered_record) { ->(created_at) { create(:catalog_plan, organization:, created_at:) } }
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
