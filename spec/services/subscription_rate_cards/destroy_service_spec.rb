# frozen_string_literal: true

require "rails_helper"

RSpec.describe SubscriptionRateCards::DestroyService do
  subject(:result) { described_class.call(subscription_rate_card:) }

  let(:organization) { create(:organization) }
  let(:subscription) { create(:subscription, :pending, organization:) }
  let(:subscription_rate_card) { create(:subscription_rate_card, organization:, subscription:) }

  it "soft deletes the entry" do
    expect(result).to be_success
    expect(result.subscription_rate_card).to be_discarded
    expect(subscription.reload.subscription_rate_cards).to be_empty
  end

  it "discards the entry's phases and their overrides" do
    rate_override = create(:rate_override, organization:)
    phase = create(:rate_phase, :subscription_level, organization:, subscription_rate_card:, position: 1, rate_override:)

    result

    expect(phase.reload).to be_discarded
    expect(rate_override.reload).to be_discarded
  end

  context "when the subscription is active" do
    let(:subscription) { create(:subscription, organization:) }

    it "forbids the deletion" do
      expect(result).not_to be_success
      expect(result.error.messages[:subscription]).to eq(["subscription_locked"])
      expect(subscription_rate_card.reload).not_to be_discarded
    end
  end

  context "when the entry is missing" do
    let(:subscription_rate_card) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("subscription_rate_card")
    end
  end
end
