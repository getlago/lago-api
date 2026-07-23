# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateCardRates::DestroyService do
  subject(:result) { described_class.call(rate_card_rate:) }

  let(:organization) { create(:organization) }
  let(:rate_card) { create(:rate_card, organization:) }

  context "with a pending rate" do
    let(:rate_card_rate) do
      create(:rate_card_rate, organization:, rate_card:, effective_datetime: 1.month.from_now)
    end

    it "soft deletes the rate" do
      expect(result).to be_success
      expect(rate_card_rate.reload).to be_discarded
    end

    it "produces a rate_card.updated activity log" do
      result
      expect(Utils::ActivityLog).to have_produced("rate_card.updated").after_commit.with(rate_card)
    end
  end

  context "with an active rate" do
    let(:rate_card_rate) do
      create(:rate_card_rate, organization:, rate_card:, effective_datetime: 1.month.ago)
    end

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:status]).to eq(["only_pending_rates_can_be_deleted"])
    end
  end

  context "when rate_card_rate is nil" do
    let(:rate_card_rate) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("rate_card_rate")
    end
  end

  context "when the card is attached to a subscription" do
    let(:rate_card_rate) do
      create(:rate_card_rate, organization:, rate_card:, effective_datetime: 1.month.from_now)
    end

    before { create(:subscription_rate_card, organization:, rate_card:) }

    it "forbids deleting the rate" do
      expect(result).not_to be_success
      expect(result.error.messages[:rate_card]).to include("attached_to_subscriptions")
    end
  end
end
