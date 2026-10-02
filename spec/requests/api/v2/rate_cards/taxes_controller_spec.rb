# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::RateCards::TaxesController do
  let(:organization) { create(:organization) }
  let(:rate_card) { create(:rate_card, organization:) }

  describe "GET /api/v2/rate_cards/:rate_card_code/taxes" do
    subject { get_with_token(organization, "/api/v2/rate_cards/#{rate_card_code}/taxes", params) }

    let(:rate_card_code) { rate_card.code }
    let(:params) { {} }
    let(:tax) { create(:tax, organization:) }

    before do
      create(:rate_card_applied_tax, rate_card:, tax:)
      create(:rate_card_applied_tax, rate_card: create(:rate_card, organization:))
      # Discarded directly: Taxes::DestroyService would delete the link as well.
      create(:rate_card_applied_tax, rate_card:).tax.discard!
    end

    include_examples "requires API permission", "rate_card", "read"

    it "returns the kept taxes of the rate card, without counts" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:taxes].map { it[:lago_id] }).to eq([tax.id])
      expect(json[:taxes].sole.keys).to eq(%i[lago_id name code rate description applied_to_organization created_at deleted_at])
      expect(json[:taxes].sole).to include(code: tax.code, deleted_at: nil)
      expect(json[:meta]).to eq(next_cursor: nil, prev_cursor: nil)
    end

    context "with include_total_count" do
      let(:params) { {include_total_count: true} }

      it "counts the kept taxes only" do
        subject

        expect(json[:taxes].map { it[:lago_id] }).to eq([tax.id])
        expect(json[:meta]).to eq(next_cursor: nil, prev_cursor: nil, total_count: 1)
      end
    end

    context "with an unknown rate card" do
      let(:rate_card_code) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("rate_card")
      end

      context "with an invalid limit" do
        let(:params) { {limit: 0} }

        it "rejects the pagination parameters first" do
          subject

          expect(response).to have_http_status(:bad_request)
          expect(json[:code]).to eq("invalid_pagination_limit")
        end
      end
    end

    context "with a rate card of another organization" do
      let(:rate_card_code) { create(:rate_card).code }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("rate_card")
      end
    end

    context "with expand" do
      let(:params) { {expand: %w[tax]} }

      it "returns an invalid expand error, since a list expands nothing" do
        subject

        expect(response).to have_http_status(:bad_request)
        expect(json[:error_details]).to eq(expand: {invalid_values: %w[tax], allowed_values: []})
      end
    end

    context "when the organization is not on the product catalog", product_catalog: false do
      it "returns a forbidden error" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
      end
    end

    it_behaves_like "a cursor paginated v2 endpoint", collection: :taxes, model: RateCard::AppliedTax do
      let(:paginated_path) { "/api/v2/rate_cards/#{rate_card.code}/taxes" }
      let(:create_paginated_record) { ->(created_at) { create(:rate_card_applied_tax, rate_card:, created_at:) } }
      # The list renders the taxes, while it is paged on their links to the rate card.
      let(:keyset_ids) { ->(tax_ids) { tax_ids.map { RateCard::AppliedTax.find_by!(rate_card:, tax_id: it).id } } }
      let(:other_table_record) { tax }
    end
  end
end
