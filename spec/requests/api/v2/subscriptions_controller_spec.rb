# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::SubscriptionsController do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:, pricing_type: "product_catalog") }
  let(:subscription) { create(:subscription, customer:, plan:, organization:) }

  describe "GET /api/v2/subscriptions" do
    subject { get_with_token(organization, "/api/v2/subscriptions") }

    before do
      create(:subscription_rate_card, organization:, subscription:)
      # An ended version must not inflate the grouped count.
      create(:subscription_rate_card, organization:, subscription:, started_at: 10.days.ago, ended_at: 1.day.ago)
    end

    include_examples "requires API permission", "subscription", "read"

    it "returns subscriptions in the v2 shape" do
      subject

      expect(response).to have_http_status(:success)

      result = json[:subscriptions].sole
      expect(result[:lago_id]).to eq(subscription.id)
      expect(result[:plan_code]).to eq(plan.code)
      expect(result[:applied_rate_cards_count]).to eq(1)
      expect(result).not_to have_key(:current_billing_period_started_at)
      expect(result).not_to have_key(:plan_amount_cents)
    end

    context "with a pending subscription" do
      let!(:pending_subscription) { create(:subscription, :pending, customer:, plan:, organization:) }

      it "lists only active subscriptions by default" do
        subject

        expect(json[:subscriptions].map { |s| s[:lago_id] }).to eq([subscription.id])
      end

      it "lists pending subscriptions when the status filter asks for them" do
        get_with_token(organization, "/api/v2/subscriptions?status[]=pending")

        expect(json[:subscriptions].map { |s| s[:lago_id] }).to eq([pending_subscription.id])
      end
    end
  end

  describe "GET /api/v2/subscriptions/:external_id" do
    subject { get_with_token(organization, "/api/v2/subscriptions/#{subscription.external_id}") }

    let!(:subscription_rate_card) { create(:subscription_rate_card, organization:, subscription:) }

    include_examples "requires API permission", "subscription", "read"

    it "returns the subscription with its rate card entries" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:subscription][:lago_id]).to eq(subscription.id)
      expect(json[:subscription][:applied_rate_cards].sole[:lago_id]).to eq(subscription_rate_card.id)
    end

    context "with an ended version of an entry" do
      before do
        create(:subscription_rate_card, organization:, subscription:, started_at: 10.days.ago, ended_at: 1.day.ago)
      end

      it "excludes it from the count and the list" do
        subject

        expect(json[:subscription][:applied_rate_cards_count]).to eq(1)
        expect(json[:subscription][:applied_rate_cards].sole[:lago_id]).to eq(subscription_rate_card.id)
      end
    end

    context "when the external id contains a dot" do
      let(:subscription) { create(:subscription, customer:, plan:, organization:, external_id: "sub.2026-01") }

      it "matches the full id instead of truncating at the format separator" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:subscription][:external_id]).to eq("sub.2026-01")
      end
    end

    context "when it does not exist" do
      subject { get_with_token(organization, "/api/v2/subscriptions/unknown") }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("subscription")
      end
    end
  end
end
