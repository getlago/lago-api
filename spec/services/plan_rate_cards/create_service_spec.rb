# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlanRateCards::CreateService do
  subject(:result) { described_class.call(plan:, params:) }

  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:rate_card) { create(:rate_card, organization:) }

  let(:params) { {rate_card_code: rate_card.code, units: "10"} }

  it "creates a plan product item" do
    expect { result }.to change(PlanRateCard, :count).by(1)

    plan_rate_card = result.plan_rate_card
    expect(plan_rate_card.plan).to eq(plan)
    expect(plan_rate_card.rate_card).to eq(rate_card)
    expect(plan_rate_card.units).to eq(10)
  end

  it "creates a default rate phase" do
    expect { result }.to change(RatePhase, :count).by(1)

    rate_phase = result.plan_rate_card.rate_phases.first
    expect(rate_phase.position).to eq(1)
    expect(rate_phase.billing_interval_cycle_count).to be_nil
    expect(rate_phase.subscription_rate_card_id).to be_nil
  end

  context "when the plan already prices the same slice" do
    before { create(:plan_rate_card, organization:, plan:, rate_card: create(:rate_card, organization:, product_item: rate_card.product_item)) }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:rate_card]).to eq(["product_item_slice_already_priced"])
    end
  end

  context "when the plan prices a different slice of the same item" do
    before do
      filter = create(:product_item_filter, organization:, product_item: rate_card.product_item)
      scoped_card = create(:rate_card, organization:, product_item: rate_card.product_item, product_item_filter: filter)
      create(:plan_rate_card, organization:, plan:, rate_card: scoped_card)
    end

    it "creates the entry" do
      expect(result).to be_success
    end
  end

  context "when the rate card currency does not match the plan currency" do
    let(:rate_card) { create(:rate_card, organization:, currency: "USD") }

    it "rejects the attachment at configuration time" do
      expect { result }.not_to change(PlanRateCard, :count)

      expect(result).not_to be_success
      expect(result.error.messages[:currency]).to eq(["currencies_does_not_match"])
    end
  end

  context "when the plan is missing" do
    let(:plan) { nil }

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

  context "when the plan has subscriptions" do
    before { create(:subscription, plan:, organization:) }

    it "forbids adding a rate card" do
      expect(result).not_to be_success
      expect(result.error.messages[:plan]).to eq(["plan_locked"])
    end
  end
end
