# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::SubscriptionRateCardsController do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, :pending, customer:, organization:) }
  let(:rate_card) { create(:rate_card, organization:) }

  describe "POST /api/v2/subscriptions/:external_id/rate_cards" do
    subject { post_with_token(organization, "/api/v2/subscriptions/#{external_id}/rate_cards", {subscription_rate_card: create_params}) }

    let(:external_id) { subscription.external_id }
    let(:create_params) do
      {rate_card_code: rate_card.code, units: "10"}
    end

    include_examples "requires API permission", "subscription_rate_card", "write"

    it "attaches the rate card to the subscription with a default rate phase" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:subscription_rate_card][:lago_id]).to be_present
      expect(json[:subscription_rate_card][:external_subscription_id]).to eq(subscription.external_id)
      expect(json[:subscription_rate_card][:rate_card_code]).to eq(rate_card.code)
      expect(json[:subscription_rate_card][:external_subscription_id]).to eq(subscription.external_id)
      expect(json[:subscription_rate_card][:rate_card_code]).to eq(rate_card.code)
      expect(json[:subscription_rate_card][:rate_phases_count]).to eq(1)
    end

    context "with a nested rate_phases sequence" do
      let(:create_params) do
        {
          rate_card_code: rate_card.code,
          units: "1",
          rate_phases: [
            {position: 1, name: "Launch", billing_interval_cycle_count: 3, rate_override: {rate_model: "standard", rate_properties: {amount: "0.02"}}},
            {position: 2, name: "Standard", billing_interval_cycle_count: nil}
          ]
        }
      end

      it "creates the entry with the provided phases and overrides in one call" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:subscription_rate_card][:rate_phases_count]).to eq(2)
        expect(RateOverride.count).to eq(1)
      end
    end

    context "when the subscription does not exist" do
      let(:external_id) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("subscription")
      end
    end

    context "when the rate card does not exist" do
      let(:create_params) { {rate_card_code: "unknown"} }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("rate_card")
      end
    end

    context "when the subscription is active" do
      let(:subscription) { create(:subscription, customer:, organization:) }

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "GET /api/v2/subscriptions/:external_id/rate_cards" do
    subject { get_with_token(organization, "/api/v2/subscriptions/#{external_id}/rate_cards") }

    let(:external_id) { subscription.external_id }
    let!(:subscription_rate_card) { create(:subscription_rate_card, organization:, subscription:) }

    before { create(:subscription_rate_card, organization:) }

    include_examples "requires API permission", "subscription_rate_card", "read"

    it "returns the subscription's entries only" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:subscription_rate_cards].map { |i| i[:lago_id] }).to eq([subscription_rate_card.id])
    end

    context "when the subscription does not exist" do
      let(:external_id) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("subscription")
      end
    end
  end

  describe "GET /api/v2/subscription_rate_cards/:id" do
    subject { get_with_token(organization, "/api/v2/subscriptions/#{subscription.external_id}/rate_cards/#{subscription_rate_card.rate_card.code}") }

    let(:subscription_rate_card) { create(:subscription_rate_card, organization:, subscription:) }

    include_examples "requires API permission", "subscription_rate_card", "read"

    it "returns the subscription product item" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:subscription_rate_card][:lago_id]).to eq(subscription_rate_card.id)
    end

    context "when it does not exist" do
      subject { get_with_token(organization, "/api/v2/subscriptions/#{subscription.external_id}/rate_cards/unknown") }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("subscription_rate_card")
      end
    end
  end

  describe "PUT /api/v2/subscription_rate_cards/:id" do
    subject { put_with_token(organization, "/api/v2/subscriptions/#{subscription.external_id}/rate_cards/#{subscription_rate_card.rate_card.code}", {subscription_rate_card: {units: "12"}}) }

    let(:subscription_rate_card) { create(:subscription_rate_card, organization:, subscription:, units: 5) }

    include_examples "requires API permission", "subscription_rate_card", "write"

    it "updates the entry" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:subscription_rate_card][:units]).to eq("12.0")
    end

    context "when the subscription is active" do
      let(:subscription) { create(:subscription, customer:, organization:) }

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "when it does not exist" do
      subject { put_with_token(organization, "/api/v2/subscriptions/#{subscription.external_id}/rate_cards/unknown", {subscription_rate_card: {units: "12"}}) }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("subscription_rate_card")
      end
    end
  end

  describe "DELETE /api/v2/subscription_rate_cards/:id" do
    subject { delete_with_token(organization, "/api/v2/subscriptions/#{subscription.external_id}/rate_cards/#{subscription_rate_card.rate_card.code}") }

    let(:subscription_rate_card) { create(:subscription_rate_card, organization:, subscription:) }

    include_examples "requires API permission", "subscription_rate_card", "write"

    it "soft deletes the entry" do
      subject

      expect(response).to have_http_status(:success)
      expect(subscription.reload.subscription_rate_cards).to be_empty
    end

    context "when the subscription is active" do
      let(:subscription) { create(:subscription, customer:, organization:) }

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
