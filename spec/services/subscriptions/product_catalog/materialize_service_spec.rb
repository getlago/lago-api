# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::ProductCatalog::MaterializeService do
  subject(:result) { described_class.call(subscription:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:, pricing_type: "product_catalog") }
  let(:subscription) { create(:subscription, customer:, plan:, started_at: Time.current) }

  let(:rate_card) { create(:rate_card, organization:) }

  before do
    create(:plan_rate_card, organization:, plan:, rate_card:, units: 5)
  end

  it "materializes the plan's rate cards onto the subscription" do
    expect { result }.to change(SubscriptionRateCard, :count).by(1)

    item = subscription.reload.applied_rate_cards.sole
    expect(item.rate_card).to eq(rate_card)
    expect(item.units).to eq(5)
    expect(item.started_at).to eq(subscription.started_at)
    expect(item.billing_anchor_date).to eq(subscription.started_at.to_date)
    expect(item.next_billing_at).to eq(subscription.started_at)
    expect(result.subscription_rate_cards).to eq([item])
  end

  context "when the subscription carries its own billing anchor" do
    let(:subscription) do
      create(:subscription, customer:, plan:, started_at: Time.zone.parse("2026-01-15"), billing_anchor_date: Date.new(2026, 1, 1))
    end

    it "materializes cards on the subscription's anchor, not its start date" do
      result

      expect(subscription.reload.applied_rate_cards.sole.billing_anchor_date).to eq(Date.new(2026, 1, 1))
    end
  end

  # next_billing_at is the clock's queue key: the instant this card should next be looked
  # at. Every case below fixes when the first cycle becomes billable.
  describe "next_billing_at" do
    subject(:next_billing_at) { result.subscription_rate_cards.sole.next_billing_at }

    let(:subscription) do
      create(:subscription, customer:, plan:, started_at:, billing_anchor_date: Date.new(2026, 1, 1))
    end
    let(:started_at) { Time.utc(2026, 1, 15, 14, 30) }
    let(:now) { Time.utc(2026, 1, 15, 14, 30) }

    before do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2025, 1, 1))
    end

    around { |example| travel_to(now) { example.run } }

    it "waits for the first period to close in arrears" do
      expect(next_billing_at).to eq(Time.utc(2026, 2, 1))
    end

    context "when the rate card bills in advance" do
      let(:rate_card) { create(:rate_card, :advance, organization:) }

      # Billable as soon as the cycle opens, and the cycle opens at the start of the
      # signing day rather than at 14:30.
      it "bills from the start of the day the card was signed" do
        expect(next_billing_at).to eq(Time.utc(2026, 1, 15))
      end
    end

    # The subscription is backdated by nearly three months. Those periods are not billed:
    # the card joins the calendar at the period it lands in today.
    context "when the subscription is backdated" do
      let(:started_at) { Time.utc(2025, 12, 15) }
      let(:now) { Time.utc(2026, 3, 10, 12, 0) }

      it "starts from the current period rather than back-billing the gap" do
        expect(next_billing_at).to eq(Time.utc(2026, 4, 1))
      end
    end

    # QA plan PH3: the first phase sets the cadence, so seeding the clock on the card's own
    # monthly interval would put the first look a whole month late.
    context "when the first rate phase overrides the interval" do
      before do
        create(
          :rate_phase,
          organization:,
          plan_rate_card: plan.applied_rate_cards.sole,
          position: 1,
          billing_interval_cycle_count: 2,
          rate_override: create(:rate_override, organization:, billing_interval_count: 1, billing_interval_unit: "week")
        )
      end

      it "seeds the clock on the phase's cadence, not the card's" do
        expect(next_billing_at).to eq(Time.utc(2026, 1, 22))
      end
    end
  end

  it "does not copy the plan entry's phases: pricing resolves by reference" do
    plan_rate_card = plan.applied_rate_cards.sole
    create(:rate_phase, organization:, plan_rate_card:, position: 1)

    expect { result }.not_to change(RatePhase, :count)
    expect(subscription.reload.applied_rate_cards.sole.rate_phases).to be_empty
  end

  context "when the plan is not a product catalog plan" do
    let(:plan) { create(:plan, organization:, pricing_type: "legacy") }

    it "does not materialize anything" do
      expect { result }.not_to change(SubscriptionRateCard, :count)
      expect(result.subscription_rate_cards).to be_nil
    end
  end
end
