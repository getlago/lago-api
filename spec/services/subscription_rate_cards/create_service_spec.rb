# frozen_string_literal: true

require "rails_helper"

RSpec.describe SubscriptionRateCards::CreateService do
  subject(:result) { described_class.call(subscription:, params:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, :pending, customer:, organization:) }
  let(:rate_card) { create(:rate_card, organization:) }

  let(:params) { {rate_card_code: rate_card.code, units: "10"} }

  it "attaches the rate card to the subscription" do
    expect { result }.to change(SubscriptionRateCard, :count).by(1)

    subscription_rate_card = result.subscription_rate_card
    expect(subscription_rate_card.subscription).to eq(subscription)
    expect(subscription_rate_card.rate_card).to eq(rate_card)
    expect(subscription_rate_card.units).to eq(10)
    expect(subscription_rate_card.billing_anchor_date).to eq(subscription_rate_card.started_at.to_date)
  end

  it "creates a default rate phase" do
    expect { result }.to change(RatePhase, :count).by(1)

    rate_phase = result.subscription_rate_card.rate_phases.first
    expect(rate_phase.position).to eq(1)
    expect(rate_phase.billing_interval_cycle_count).to be_nil
    expect(rate_phase.plan_rate_card_id).to be_nil
  end

  context "with explicit dates" do
    let(:params) do
      {
        rate_card_code: rate_card.code,
        started_at: "2026-08-01T00:00:00Z",
        billing_anchor_date: "2026-08-15"
      }
    end

    it "uses them" do
      subscription_rate_card = result.subscription_rate_card
      expect(subscription_rate_card.started_at).to eq(Time.zone.parse("2026-08-01"))
      expect(subscription_rate_card.billing_anchor_date).to eq(Date.parse("2026-08-15"))
      expect(subscription_rate_card.next_billing_at).to eq(Time.zone.parse("2026-08-01"))
    end
  end

  context "with a nested rate_phases sequence" do
    let(:params) do
      {
        rate_card_code: rate_card.code,
        units: "1",
        rate_phases: [
          {position: 1, name: "Launch", billing_interval_cycle_count: 3},
          {position: 2, name: "Standard", billing_interval_cycle_count: nil}
        ]
      }
    end

    it "creates the entry with the provided phases instead of the default" do
      expect(result).to be_success
      expect(result.subscription_rate_card.rate_phases.order(:position).pluck(:name)).to eq(%w[Launch Standard])
    end
  end

  context "with an invalid nested rate_phases sequence" do
    let(:params) do
      {
        rate_card_code: rate_card.code,
        rate_phases: [
          {position: 1, billing_interval_cycle_count: 3},
          {position: 3, billing_interval_cycle_count: nil}
        ]
      }
    end

    it "fails and rolls the whole create back" do
      expect { result }.not_to change(SubscriptionRateCard, :count)
      expect(result).not_to be_success
      expect(result.error.messages[:rate_phases]).to eq(["non_contiguous_position"])
    end
  end

  context "when the rate card currency does not match the plan currency" do
    let(:rate_card) { create(:rate_card, organization:, currency: "USD") }

    it "rejects the attachment at configuration time" do
      expect { result }.not_to change(SubscriptionRateCard, :count)

      expect(result).not_to be_success
      expect(result.error.messages[:currency]).to eq(["currencies_does_not_match"])
    end
  end

  context "when the subscription is missing" do
    let(:subscription) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::NotFoundFailure)
    end
  end

  context "when the rate card does not exist" do
    let(:params) { {rate_card_code: "unknown"} }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("rate_card")
    end
  end

  context "when the rate card is already attached and live" do
    before { create(:subscription_rate_card, organization:, subscription:, rate_card:) }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:rate_card]).to eq(["product_item_slice_already_priced"])
    end
  end

  context "when the subscription is active" do
    let(:subscription) { create(:subscription, customer:, organization:) }

    it "forbids attaching a rate card" do
      expect(result).not_to be_success
      expect(result.error.messages[:subscription]).to eq(["subscription_locked"])
    end
  end

  context "when the subscription already prices the same slice" do
    before do
      other_card = create(:rate_card, organization:, product_item: rate_card.product_item)
      create(:subscription_rate_card, organization:, subscription:, rate_card: other_card)
    end

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:rate_card]).to eq(["product_item_slice_already_priced"])
    end
  end
end
