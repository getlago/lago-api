# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::SubscriptionRateCards::RatePhasesController do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, :pending, customer:, organization:) }
  let(:rate_card) { create(:rate_card, organization:) }
  let(:subscription_rate_card) { create(:subscription_rate_card, organization:, subscription:, rate_card:) }

  describe "GET /api/v2/subscription_rate_cards/:subscription_rate_card_id/rate_phases" do
    subject { get_with_token(organization, "/api/v2/subscriptions/#{subscription.external_id}/rate_cards/#{subscription_rate_card.rate_card.code}/rate_phases") }

    let!(:rate_phase) { create(:rate_phase, :subscription_level, organization:, subscription_rate_card:, position: 1) }

    include_examples "requires API permission", "subscription_rate_card", "read"

    it "returns the entry's rate phases" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:rate_phases].map { |phase| phase[:lago_id] }).to eq([rate_phase.id])
    end

    context "when the subscription product item does not exist" do
      subject { get_with_token(organization, "/api/v2/subscriptions/#{subscription.external_id}/rate_cards/unknown/rate_phases") }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("subscription_rate_card")
      end
    end
  end

  describe "PUT /api/v2/subscription_rate_cards/:subscription_rate_card_id/rate_phases" do
    subject do
      put_with_token(organization, "/api/v2/subscriptions/#{subscription.external_id}/rate_cards/#{subscription_rate_card.rate_card.code}/rate_phases", {rate_phases: phases})
    end

    let(:phases) do
      [
        {position: 1, name: "ramp", billing_interval_cycle_count: 3},
        {position: 2, name: "standard", billing_interval_cycle_count: nil}
      ]
    end

    include_examples "requires API permission", "subscription_rate_card", "write"

    it "replaces the phase sequence" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:rate_phases].map { |phase| phase[:position] }).to eq([1, 2])
      expect(json[:rate_phases].map { |phase| phase[:name] }).to eq(%w[ramp standard])
    end

    it "replaces an existing sequence while the subscription is pending" do
      create(:rate_phase, :subscription_level, organization:, subscription_rate_card:, position: 1)

      subject

      expect(response).to have_http_status(:success)
      expect(subscription_rate_card.rate_phases.order(:position).map(&:name)).to eq(%w[ramp standard])
    end

    context "when the subscription is active" do
      let(:subscription) { create(:subscription, customer:, organization:) }

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "with a rate override on a phase" do
      let(:phases) do
        [
          {
            position: 1,
            name: "ramp",
            billing_interval_cycle_count: 3,
            rate_override: {rate_model: "standard", rate_properties: {amount: "0"}, min_amount_cents: 0}
          },
          {position: 2, billing_interval_cycle_count: nil}
        ]
      end

      it "creates the override and returns it on the phase" do
        subject

        expect(response).to have_http_status(:success)
        override = json[:rate_phases].first[:rate_override]
        expect(override[:lago_id]).to be_present
        expect(override[:rate_model]).to eq("standard")
        expect(json[:rate_phases].last[:rate_override]).to be_nil
      end
    end

    context "when positions are not contiguous" do
      let(:phases) do
        [
          {position: 1, billing_interval_cycle_count: 3},
          {position: 3, billing_interval_cycle_count: nil}
        ]
      end

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
