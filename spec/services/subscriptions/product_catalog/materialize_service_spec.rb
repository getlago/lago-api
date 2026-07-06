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

    item = subscription.reload.subscription_rate_cards.sole
    expect(item.rate_card).to eq(rate_card)
    expect(item.units).to eq(5)
    expect(item.started_at).to eq(subscription.started_at)
    expect(item.billing_anchor_date).to eq(subscription.started_at.to_date)
    expect(item.next_billing_at).to eq(subscription.started_at)
    expect(result.subscription_rate_cards).to eq([item])
  end

  it "does not copy the plan entry's phases: pricing resolves by reference" do
    plan_rate_card = plan.plan_rate_cards.sole
    create(:rate_phase, organization:, plan_rate_card:, position: 1)

    expect { result }.not_to change(RatePhase, :count)
    expect(subscription.reload.subscription_rate_cards.sole.rate_phases).to be_empty
  end

  context "when the plan is not a product catalog plan" do
    let(:plan) { create(:plan, organization:, pricing_type: "legacy") }

    it "does not materialize anything" do
      expect { result }.not_to change(SubscriptionRateCard, :count)
      expect(result.subscription_rate_cards).to be_nil
    end
  end
end
