# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::RateCardsController do
  let(:organization) { create(:organization) }
  let(:product) { create(:product, organization:) }

  describe "POST /api/v2/rate_cards" do
    subject { post_with_token(organization, "/api/v2/rate_cards", {rate_card: create_params}) }

    let(:create_params) do
      {
        product_code: product.code,
        name: "Standard",
        code: "standard",
        currency: "EUR"
      }
    end

    include_examples "requires API permission", "rate_card", "write"

    it "creates the rate card" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:rate_card][:lago_id]).to be_present
      expect(json[:rate_card][:product_code]).to eq(product.code)
      expect(json[:rate_card][:code]).to eq("standard")
      expect(json[:rate_card][:currency]).to eq("EUR")
      expect(json[:rate_card][:taxes]).to eq([])
    end

    context "with taxes" do
      let(:tax1) { create(:tax, organization:) }
      let(:tax2) { create(:tax, organization:) }

      before { create_params[:tax_codes] = [tax1.code, tax2.code] }

      it "applies and returns the taxes" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:rate_card][:taxes].pluck(:code)).to match_array([tax1.code, tax2.code])
      end

      context "when a tax belongs to another organization" do
        let(:other_tax) { create(:tax) }

        before { create_params[:tax_codes] = [other_tax.code] }

        it "returns a tax not found error" do
          expect { subject }.not_to change(RateCard, :count)

          expect(response).to be_not_found_error("tax")
        end
      end
    end

    context "when the product does not exist" do
      let(:create_params) { {product_code: "unknown", name: "Standard", code: "standard", currency: "EUR"} }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("product")
      end
    end

    context "with nested rates" do
      let(:create_params) do
        {
          product_code: product.code,
          name: "Standard",
          code: "standard",
          currency: "EUR",
          rates: [
            {
              code: "launch_price",
              effective_from: 1.minute.ago.to_date.iso8601,
              rate_model: "standard",
              rate_properties: {amount: "0.05"},
              billing_interval_count: 1,
              billing_interval_unit: "month"
            },
            {
              code: "standard_price",
              effective_from: 1.month.from_now.to_date.iso8601,
              rate_model: "standard",
              rate_properties: {amount: "0.07"},
              billing_interval_unit: "month"
            }
          ]
        }
      end

      it "creates the card with its rates in one call" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:rate_card][:rates_count]).to eq(2)
      end

      context "when a nested rate is invalid" do
        let(:create_params) do
          {
            product_code: product.code,
            name: "Standard",
            code: "standard",
            currency: "EUR",
            rates: [
              {code: "bad", effective_from: Time.current.to_date.iso8601, rate_model: "standard", rate_properties: {}, billing_interval_unit: "month"}
            ]
          }
        end

        it "rolls the whole create back with prefixed error keys" do
          subject

          expect(response).to have_http_status(:unprocessable_entity)
          expect(json.dig(:error_details, :"rates.rate_properties")).to be_present
          expect(RateCard.count).to eq(0)
        end
      end
    end

    context "with a product_filter_code" do
      let(:product_filter) { create(:product_filter, organization:, product:) }
      let(:create_params) do
        {
          product_code: product.code,
          product_filter_code: product_filter.code,
          name: "Standard",
          code: "standard",
          currency: "EUR"
        }
      end

      it "creates a filter-scoped rate card" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:rate_card][:product_filter_code]).to eq(product_filter.code)
      end

      context "when the filter does not exist" do
        let(:create_params) do
          {
            product_code: product.code,
            product_filter_code: "unknown",
            name: "Standard",
            code: "standard",
            currency: "EUR"
          }
        end

        it "returns a not found error" do
          subject

          expect(response).to be_not_found_error("product_filter")
        end
      end

      context "when the product_filter_code is null" do
        let(:create_params) do
          {
            product_code: product.code,
            product_filter_code: nil,
            name: "Standard",
            code: "standard",
            currency: "EUR"
          }
        end

        it "creates an unfiltered rate card" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:rate_card][:product_filter_code]).to be_nil
        end
      end
    end

    context "when the currency is invalid" do
      let(:create_params) { {product_code: product.code, name: "Standard", code: "standard", currency: "ABC"} }

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "PUT /api/v2/rate_cards/:code" do
    subject { put_with_token(organization, "/api/v2/rate_cards/#{rate_card.code}", {rate_card: update_params}) }

    let(:rate_card) { create(:rate_card, organization:, product:, name: "Before") }
    let(:update_params) { {name: "After"} }

    include_examples "requires API permission", "rate_card", "write"

    it "updates the rate card" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:rate_card][:name]).to eq("After")
    end

    context "with taxes" do
      let(:tax1) { create(:tax, organization:) }
      let(:tax2) { create(:tax, organization:) }
      let(:update_params) { {tax_codes: [tax2.code]} }

      before { create(:rate_card_applied_tax, rate_card:, tax: tax1, organization:) }

      it "replaces and returns the taxes" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:rate_card][:taxes].pluck(:code)).to eq([tax2.code])
      end

      context "when tax codes are empty" do
        let(:update_params) { {tax_codes: []} }

        it "removes the tax override" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:rate_card][:taxes]).to eq([])
        end
      end

      context "when tax codes are null" do
        let(:update_params) { {tax_codes: nil} }

        it "keeps the existing tax" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:rate_card][:taxes].pluck(:code)).to eq([tax1.code])
        end
      end

      context "when a tax belongs to another organization" do
        let(:other_tax) { create(:tax) }
        let(:update_params) { {tax_codes: [other_tax.code]} }

        it "returns a tax not found error and keeps the existing tax" do
          subject

          expect(response).to be_not_found_error("tax")
          expect(rate_card.reload.taxes).to eq([tax1])
        end
      end
    end

    context "when the rate card does not exist" do
      subject { put_with_token(organization, "/api/v2/rate_cards/unknown", {rate_card: update_params}) }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("rate_card")
      end
    end
  end

  describe "GET /api/v2/rate_cards/:code" do
    subject { get_with_token(organization, "/api/v2/rate_cards/#{rate_card.code}") }

    let(:rate_card) { create(:rate_card, organization:, product:) }

    include_examples "requires API permission", "rate_card", "read"

    it "returns the rate card with its rates count, active rate, and taxes" do
      tax = create(:tax, organization:)
      create(:rate_card_applied_tax, rate_card:, tax:, organization:)
      create(:rate_card_rate, organization:, rate_card:, effective_from: 1.day.ago.beginning_of_day)

      subject

      expect(response).to have_http_status(:success)
      expect(json[:rate_card][:lago_id]).to eq(rate_card.id)
      expect(json[:rate_card][:rates_count]).to eq(1)
      expect(json[:rate_card][:active_rate][:status]).to eq("active")
      expect(json[:rate_card][:taxes].pluck(:code)).to eq([tax.code])
    end

    context "when the rate card belongs to another organization" do
      let(:rate_card) { create(:rate_card) }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("rate_card")
      end
    end
  end

  describe "GET /api/v2/rate_cards" do
    subject { get_with_token(organization, "/api/v2/rate_cards#{query_params}") }

    let(:query_params) { "" }
    let!(:rate_card) { create(:rate_card, organization:, product:, name: "Matching") }
    let!(:other) { create(:rate_card, organization:, name: "Other") }

    include_examples "requires API permission", "rate_card", "read"

    it "returns the rate cards" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:rate_cards].map { it[:lago_id] }).to match_array([rate_card.id, other.id])
    end

    context "with a product_id filter" do
      let(:query_params) { "?product_id=#{product.id}" }

      it "returns only the rate cards of that product" do
        subject

        expect(json[:rate_cards].map { it[:lago_id] }).to eq([rate_card.id])
      end
    end

    context "with a product_code filter" do
      let(:query_params) { "?product_code=#{product.code}" }

      it "returns only the rate cards of that product" do
        subject

        expect(json[:rate_cards].map { it[:lago_id] }).to eq([rate_card.id])
      end
    end

    context "with a search term" do
      let(:query_params) { "?search_term=Matching" }

      it "returns only the matching rate cards" do
        subject

        expect(json[:rate_cards].map { it[:lago_id] }).to eq([rate_card.id])
      end
    end
  end

  describe "DELETE /api/v2/rate_cards/:code" do
    subject { delete_with_token(organization, "/api/v2/rate_cards/#{rate_card.code}") }

    let(:rate_card) { create(:rate_card, organization:, product:) }

    include_examples "requires API permission", "rate_card", "write"

    it "soft deletes the rate card" do
      expect { subject }.to change { rate_card.reload.discarded? }.from(false).to(true)

      expect(response).to have_http_status(:success)
      expect(json[:rate_card][:lago_id]).to eq(rate_card.id)
    end

    context "when the rate card does not exist" do
      subject { delete_with_token(organization, "/api/v2/rate_cards/unknown") }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("rate_card")
      end
    end
  end
end
