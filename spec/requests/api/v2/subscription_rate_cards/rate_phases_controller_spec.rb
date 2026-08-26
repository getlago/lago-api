# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::SubscriptionRateCards::RatePhasesController do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, :pending, customer:, organization:) }
  let(:rate_card) { create(:rate_card, organization:) }
  let(:subscription_rate_card) { create(:subscription_rate_card, organization:, subscription:, rate_card:) }

  describe "GET /api/v2/subscriptions/:external_id/applied_rate_cards/:rate_card_code/rate_phases" do
    subject { get_with_token(organization, "/api/v2/subscriptions/#{subscription.external_id}/applied_rate_cards/#{subscription_rate_card.rate_card.code}/rate_phases") }

    let!(:rate_phase) { create(:rate_phase, :subscription_level, organization:, subscription_rate_card:, position: 1) }

    include_examples "requires API permission", "subscription_rate_card", "read"

    it "returns the entry's rate phases with their codes" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:rate_phases].map { |phase| phase[:lago_id] }).to eq([rate_phase.id])
      expect(json[:rate_phases].map { |phase| phase[:code] }).to eq([rate_phase.code])
    end

    context "when the entry does not exist" do
      subject { get_with_token(organization, "/api/v2/subscriptions/#{subscription.external_id}/applied_rate_cards/unknown/rate_phases") }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("applied_rate_card")
      end
    end
  end

  describe "POST /api/v2/subscriptions/:external_id/applied_rate_cards/:rate_card_code/rate_phases" do
    subject do
      post_with_token(
        organization,
        "/api/v2/subscriptions/#{subscription.external_id}/applied_rate_cards/#{subscription_rate_card.rate_card.code}/rate_phases",
        {rate_phase: phase_params}
      )
    end

    let!(:terminal) { create(:rate_phase, :subscription_level, organization:, subscription_rate_card:, position: 1, billing_interval_cycle_count: nil) }
    let(:phase_params) do
      {
        code: "negotiated",
        billing_interval_cycle_count: 3,
        rate_override: {rate_model: "standard", rate_properties: {amount: "0.01"}}
      }
    end

    include_examples "requires API permission", "subscription_rate_card", "write"

    it "inserts the phase with its override before the indefinite tail" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:rate_phase][:code]).to eq("negotiated")
      expect(json[:rate_phase][:position]).to eq(1)
      expect(json.dig(:rate_phase, :rate_override, :rate_model)).to eq("standard")
      expect(terminal.reload.position).to eq(2)
    end

    context "when the subscription is active" do
      let(:subscription) { create(:subscription, customer:, organization:) }

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json.dig(:error_details, :rate_phase)).to eq(["subscription_locked"])
      end
    end
  end

  context "when the card starts in the future on a pending subscription" do
    let(:subscription) { create(:subscription, :pending, customer:, organization:, subscription_at: 1.month.from_now) }
    let(:subscription_rate_card) do
      create(:subscription_rate_card, organization:, subscription:, rate_card:, started_at: 1.month.from_now)
    end

    let!(:terminal) { create(:rate_phase, :subscription_level, organization:, subscription_rate_card:, position: 1, billing_interval_cycle_count: nil) }

    it "keeps the phases addressable during the authoring window" do
      get_with_token(organization, "/api/v2/subscriptions/#{subscription.external_id}/applied_rate_cards/#{rate_card.code}/rate_phases")
      expect(response).to have_http_status(:success)
      expect(json[:rate_phases].map { |phase| phase[:lago_id] }).to eq([terminal.id])

      post_with_token(
        organization,
        "/api/v2/subscriptions/#{subscription.external_id}/applied_rate_cards/#{rate_card.code}/rate_phases",
        {rate_phase: {code: "intro", billing_interval_cycle_count: 3}}
      )
      expect(response).to have_http_status(:success)
      expect(json[:rate_phase][:position]).to eq(1)
    end
  end

  describe "PUT /api/v2/subscriptions/:external_id/applied_rate_cards/:rate_card_code/rate_phases/:code" do
    subject do
      put_with_token(
        organization,
        "/api/v2/subscriptions/#{subscription.external_id}/applied_rate_cards/#{subscription_rate_card.rate_card.code}/rate_phases/#{rate_phase.code}",
        {rate_phase: {name: "Renamed"}}
      )
    end

    let!(:rate_phase) { create(:rate_phase, :subscription_level, organization:, subscription_rate_card:, position: 1, code: "negotiated") }

    include_examples "requires API permission", "subscription_rate_card", "write"

    it "updates the phase" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:rate_phase][:name]).to eq("Renamed")
    end

    context "when a position is provided" do
      subject do
        put_with_token(
          organization,
          "/api/v2/subscriptions/#{subscription.external_id}/applied_rate_cards/#{subscription_rate_card.rate_card.code}/rate_phases/#{rate_phase.code}",
          {rate_phase: {name: "Renamed", position: 4}}
        )
      end

      it "does not permit it" do
        subject

        expect(response).to have_http_status(:success)
        expect(rate_phase.reload.position).to eq(1)
      end
    end

    context "when the override is an explicit null" do
      subject do
        put_with_token(
          organization,
          "/api/v2/subscriptions/#{subscription.external_id}/applied_rate_cards/#{subscription_rate_card.rate_card.code}/rate_phases/#{rate_phase.code}",
          {rate_phase: {rate_override: nil}}
        )
      end

      let(:override) { create(:rate_override, organization:) }

      before { rate_phase.update!(rate_override_id: override.id) }

      it "clears the override" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:rate_phase][:rate_override]).to be_nil
        expect(rate_phase.reload.rate_override).to be_nil
        expect(override.reload).to be_discarded
      end
    end

    context "when the override names a structural card field" do
      subject do
        put_with_token(
          organization,
          "/api/v2/subscriptions/#{subscription.external_id}/applied_rate_cards/#{subscription_rate_card.rate_card.code}/rate_phases/#{rate_phase.code}",
          {rate_phase: {rate_override: {rate_model: "standard", rate_properties: {amount: "0.02"}, currency: "EUR"}}}
        )
      end

      it "rejects it instead of silently dropping the field" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json.dig(:error_details, :currency)).to eq(["not_overridable"])
        expect(rate_phase.reload.rate_override).to be_nil
      end
    end

    context "when the subscription is active" do
      let(:subscription) { create(:subscription, customer:, organization:) }

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json.dig(:error_details, :rate_phase)).to eq(["subscription_locked"])
      end
    end
  end

  describe "DELETE /api/v2/subscriptions/:external_id/applied_rate_cards/:rate_card_code/rate_phases/:code" do
    subject do
      delete_with_token(
        organization,
        "/api/v2/subscriptions/#{subscription.external_id}/applied_rate_cards/#{subscription_rate_card.rate_card.code}/rate_phases/#{terminal.code}"
      )
    end

    let!(:launch) { create(:rate_phase, :subscription_level, organization:, subscription_rate_card:, position: 1, billing_interval_cycle_count: 3) }
    let!(:terminal) { create(:rate_phase, :subscription_level, organization:, subscription_rate_card:, position: 2, billing_interval_cycle_count: nil) }

    include_examples "requires API permission", "subscription_rate_card", "write"

    it "deletes the phase and promotes the new last phase to indefinite" do
      subject

      expect(response).to have_http_status(:success)
      expect(terminal.reload).to be_discarded
      expect(launch.reload.billing_interval_cycle_count).to be_nil
    end
  end
end
