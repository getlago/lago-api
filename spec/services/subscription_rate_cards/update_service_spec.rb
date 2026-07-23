# frozen_string_literal: true

require "rails_helper"

RSpec.describe SubscriptionRateCards::UpdateService do
  subject(:result) { described_class.call(subscription_rate_card:, params:) }

  let(:organization) { create(:organization) }
  let(:subscription) { create(:subscription, :pending, organization:) }
  let(:subscription_rate_card) { create(:subscription_rate_card, organization:, subscription:, units: 5) }

  let(:params) { {units: "12"} }

  it "updates the entry" do
    expect(result).to be_success
    expect(result.subscription_rate_card.units).to eq(12)
  end

  context "when moving the start date" do
    let(:params) { {started_at: Time.zone.parse("2026-09-01")} }

    it "moves the billing clock along with it" do
      item = result.subscription_rate_card
      expect(item.started_at).to eq(Time.zone.parse("2026-09-01"))
      expect(item.next_billing_at).to eq(Time.zone.parse("2026-09-01"))
    end
  end

  context "when updating the billing anchor" do
    let(:params) { {billing_anchor_date: "2026-09-15"} }

    it "updates it" do
      expect(result.subscription_rate_card.billing_anchor_date).to eq(Date.parse("2026-09-15"))
    end
  end

  context "when the subscription is active" do
    let(:subscription) { create(:subscription, organization:) }

    it "forbids the update" do
      expect(result).not_to be_success
      expect(result.error.messages[:subscription]).to eq(["subscription_locked"])
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
