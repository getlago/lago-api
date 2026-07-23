# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::RateCardsController do
  let(:organization) { create(:organization) }
  let(:product_item) { create(:product_item, organization:) }

  describe "POST /api/v2/rate_cards" do
    subject { post_with_token(organization, "/api/v2/rate_cards", {rate_card: create_params}) }

    let(:create_params) do
      {
        product_item_code: product_item.code,
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
      expect(json[:rate_card][:product_item_code]).to eq(product_item.code)
      expect(json[:rate_card][:code]).to eq("standard")
      expect(json[:rate_card][:currency]).to eq("EUR")
    end

    context "when the product item does not exist" do
      let(:create_params) { {product_item_code: "unknown", name: "Standard", code: "standard", currency: "EUR"} }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("product_item")
      end
    end

    context "with nested rates" do
      let(:create_params) do
        {
          product_item_code: product_item.code,
          name: "Standard",
          code: "standard",
          currency: "EUR",
          rates: [
            {
              effective_datetime: 1.minute.ago.iso8601,
              rate_model: "standard",
              rate_properties: {amount: "0.05"},
              billing_interval_count: 1,
              billing_interval_unit: "month"
            },
            {
              effective_datetime: 1.month.from_now.iso8601,
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
            product_item_code: product_item.code,
            name: "Standard",
            code: "standard",
            currency: "EUR",
            rates: [
              {effective_datetime: Time.current.iso8601, rate_model: "standard", rate_properties: {}, billing_interval_unit: "month"}
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

    context "with a product_item_filter_code" do
      let(:product_item_filter) { create(:product_item_filter, organization:, product_item:) }
      let(:create_params) do
        {
          product_item_code: product_item.code,
          product_item_filter_code: product_item_filter.code,
          name: "Standard",
          code: "standard",
          currency: "EUR"
        }
      end

      it "creates a filter-scoped rate card" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:rate_card][:product_item_filter_code]).to eq(product_item_filter.code)
      end

      context "when the filter does not exist" do
        let(:create_params) do
          {
            product_item_code: product_item.code,
            product_item_filter_code: "unknown",
            name: "Standard",
            code: "standard",
            currency: "EUR"
          }
        end

        it "returns a not found error" do
          subject

          expect(response).to be_not_found_error("product_item_filter")
        end
      end
    end

    context "when the currency is invalid" do
      let(:create_params) { {product_item_code: product_item.code, name: "Standard", code: "standard", currency: "ABC"} }

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "PUT /api/v2/rate_cards/:code" do
    subject { put_with_token(organization, "/api/v2/rate_cards/#{rate_card.code}", {rate_card: update_params}) }

    let(:rate_card) { create(:rate_card, organization:, product_item:, name: "Before") }
    let(:update_params) { {name: "After"} }

    include_examples "requires API permission", "rate_card", "write"

    it "updates the rate card" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:rate_card][:name]).to eq("After")
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

    let(:rate_card) { create(:rate_card, organization:, product_item:) }

    include_examples "requires API permission", "rate_card", "read"

    it "returns the rate card with its rates count and active rate" do
      create(:rate_card_rate, organization:, rate_card:, effective_datetime: 1.day.ago)

      subject

      expect(response).to have_http_status(:success)
      expect(json[:rate_card][:lago_id]).to eq(rate_card.id)
      expect(json[:rate_card][:rates_count]).to eq(1)
      expect(json[:rate_card][:active_rate][:status]).to eq("active")
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
    let!(:rate_card) { create(:rate_card, organization:, product_item:, name: "Matching") }
    let!(:other) { create(:rate_card, organization:, name: "Other") }

    include_examples "requires API permission", "rate_card", "read"

    it "returns the rate cards" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:rate_cards].map { it[:lago_id] }).to match_array([rate_card.id, other.id])
    end

    context "with a product_item_id filter" do
      let(:query_params) { "?product_item_id=#{product_item.id}" }

      it "returns only the rate cards of that product item" do
        subject

        expect(json[:rate_cards].map { it[:lago_id] }).to eq([rate_card.id])
      end
    end

    context "with a product_item_code filter" do
      let(:query_params) { "?product_item_code=#{product_item.code}" }

      it "returns only the rate cards of that product item" do
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

    let(:rate_card) { create(:rate_card, organization:, product_item:) }

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
