# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::RateCards::RatesController do
  let(:organization) { create(:organization) }
  let(:rate_card) { create(:rate_card, organization:) }

  describe "POST /api/v2/rate_cards/:rate_card_id/rates" do
    subject { post_with_token(organization, "/api/v2/rate_cards/#{rate_card.id}/rates", {rate: create_params}) }

    let(:create_params) do
      {
        effective_datetime: 1.month.from_now.iso8601,
        rate_model: "standard",
        rate_properties: {amount: "12"},
        billing_interval_unit: "month"
      }
    end

    include_examples "requires API permission", "rate_card", "write"

    it "appends a rate to the rate card" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:rate][:lago_id]).to be_present
      expect(json[:rate][:rate_model]).to eq("standard")
      expect(json[:rate][:status]).to eq("pending")
    end

    context "when the rate card does not exist" do
      subject { post_with_token(organization, "/api/v2/rate_cards/#{SecureRandom.uuid}/rates", {rate: create_params}) }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("rate_card")
      end
    end
  end

  describe "PUT /api/v2/rate_cards/:rate_card_id/rates/:id" do
    subject { put_with_token(organization, "/api/v2/rate_cards/#{rate_card.id}/rates/#{rate.id}", {rate: update_params}) }

    let(:rate) { create(:rate_card_rate, organization:, rate_card:, effective_datetime: 1.month.from_now) }
    let(:update_params) { {min_amount_cents: 500} }

    it "updates the pending rate" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:rate][:min_amount_cents]).to eq(500)
    end

    context "when the rate does not exist" do
      subject { put_with_token(organization, "/api/v2/rate_cards/#{rate_card.id}/rates/#{SecureRandom.uuid}", {rate: update_params}) }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("rate_card_rate")
      end
    end
  end

  describe "GET /api/v2/rate_cards/:rate_card_id/rates/:id" do
    subject { get_with_token(organization, "/api/v2/rate_cards/#{rate_card.id}/rates/#{rate.id}") }

    let(:rate) { create(:rate_card_rate, organization:, rate_card:) }

    include_examples "requires API permission", "rate_card", "read"

    it "returns the rate" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:rate][:lago_id]).to eq(rate.id)
    end
  end

  describe "GET /api/v2/rate_cards/:rate_card_id/rates" do
    subject { get_with_token(organization, "/api/v2/rate_cards/#{rate_card.id}/rates") }

    let!(:rate) { create(:rate_card_rate, organization:, rate_card:) }

    before { create(:rate_card_rate, organization:) }

    include_examples "requires API permission", "rate_card", "read"

    it "returns only the rates of the rate card" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:rates].map { it[:lago_id] }).to eq([rate.id])
    end
  end

  describe "DELETE /api/v2/rate_cards/:rate_card_id/rates/:id" do
    subject { delete_with_token(organization, "/api/v2/rate_cards/#{rate_card.id}/rates/#{rate.id}") }

    context "when the rate is pending" do
      let(:rate) { create(:rate_card_rate, organization:, rate_card:, effective_datetime: 1.month.from_now) }

      it "deletes the rate" do
        expect { subject }.to change { rate.reload.discarded? }.from(false).to(true)
        expect(response).to have_http_status(:success)
      end
    end

    context "when the rate is active" do
      let(:rate) { create(:rate_card_rate, organization:, rate_card:, effective_datetime: 1.day.ago) }

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
