# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::RateCards::RatesController do
  let(:organization) { create(:organization) }
  let(:rate_card) { create(:rate_card, organization:) }

  describe "POST /api/v2/rate_cards/:rate_card_id/rates" do
    subject { post_with_token(organization, "/api/v2/rate_cards/#{rate_card.code}/rates", {rate: create_params}) }

    let(:create_params) do
      {
        code: "launch_price",
        effective_from: 1.month.from_now.to_date.iso8601,
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

    it "returns effective_from as a midnight datetime on an arrears card" do
      subject

      expect(json[:rate][:effective_from]).to eq(1.month.from_now.beginning_of_day.iso8601)
    end

    context "when an arrears card receives a datetime string" do
      before { create_params[:effective_from] = "2026-12-01T17:00:00Z" }

      it "canonicalizes it to its day's midnight" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:rate][:effective_from]).to eq("2026-12-01T00:00:00Z")
      end

      context "when the day already has a rate" do
        before { create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2026-12-01")) }

        it "returns a value_already_exist error" do
          subject

          expect(response).to have_http_status(:unprocessable_entity)
          expect(json.dig(:error_details, :effective_from)).to eq(["value_already_exist"])
        end
      end
    end

    context "with an advance card" do
      let(:rate_card) { create(:rate_card, organization:, billing_timing: "advance") }

      before { create_params[:effective_from] = "2026-12-01T17:00:00Z" }

      it "accepts a datetime and returns it in full" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:rate][:effective_from]).to eq("2026-12-01T17:00:00Z")
      end
    end

    context "when effective_from is unparseable" do
      before { create_params[:effective_from] = "hello" }

      it "returns value_is_invalid rather than value_is_mandatory" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json.dig(:error_details, :effective_from)).to eq(["value_is_invalid"])
      end
    end

    context "when effective_from is omitted" do
      before { create_params.delete(:effective_from) }

      it "returns value_is_mandatory" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json.dig(:error_details, :effective_from)).to eq(["value_is_mandatory"])
      end
    end

    context "when the rate card does not exist" do
      subject { post_with_token(organization, "/api/v2/rate_cards/unknown/rates", {rate: create_params}) }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("rate_card")
      end
    end
  end

  describe "PUT /api/v2/rate_cards/:rate_card_id/rates/:code" do
    subject { put_with_token(organization, "/api/v2/rate_cards/#{rate_card.code}/rates/#{rate.code}", {rate: update_params}) }

    let(:rate) { create(:rate_card_rate, organization:, rate_card:, effective_from: 1.month.from_now.beginning_of_day) }
    let(:update_params) { {min_amount_cents: 500} }

    context "when updating the code on an unattached card" do
      let(:update_params) { {code: "renamed"} }

      it "updates the code" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:rate][:code]).to eq("renamed")
      end
    end

    it "updates the pending rate" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:rate][:min_amount_cents]).to eq(500)
    end

    context "when the rate does not exist" do
      subject { put_with_token(organization, "/api/v2/rate_cards/#{rate_card.code}/rates/unknown", {rate: update_params}) }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("rate_card_rate")
      end
    end
  end

  describe "GET /api/v2/rate_cards/:rate_card_id/rates/:code" do
    subject { get_with_token(organization, "/api/v2/rate_cards/#{rate_card.code}/rates/#{rate.code}") }

    let(:rate) { create(:rate_card_rate, organization:, rate_card:) }

    include_examples "requires API permission", "rate_card", "read"

    it "returns the rate" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:rate][:lago_id]).to eq(rate.id)
    end
  end

  describe "GET /api/v2/rate_cards/:rate_card_id/rates" do
    subject { get_with_token(organization, "/api/v2/rate_cards/#{rate_card.code}/rates") }

    let!(:rate) { create(:rate_card_rate, organization:, rate_card:) }

    before { create(:rate_card_rate, organization:) }

    include_examples "requires API permission", "rate_card", "read"

    it "returns only the rates of the rate card" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:rates].map { it[:lago_id] }).to eq([rate.id])
    end
  end

  describe "DELETE /api/v2/rate_cards/:rate_card_id/rates/:code" do
    subject { delete_with_token(organization, "/api/v2/rate_cards/#{rate_card.code}/rates/#{rate.code}") }

    context "when the rate is pending" do
      let(:rate) { create(:rate_card_rate, organization:, rate_card:, effective_from: 1.month.from_now.beginning_of_day) }

      it "deletes the rate" do
        expect { subject }.to change { rate.reload.discarded? }.from(false).to(true)
        expect(response).to have_http_status(:success)
      end
    end

    context "when the rate is active" do
      let(:rate) { create(:rate_card_rate, organization:, rate_card:, effective_from: 1.day.ago.beginning_of_day) }

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
