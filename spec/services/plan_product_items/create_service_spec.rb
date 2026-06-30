# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlanProductItems::CreateService do
  subject(:result) { described_class.call(plan:, params:) }

  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:product_item) { create(:product_item, organization:) }
  let(:rate_card) { create(:rate_card, organization:, product_item:) }

  let(:params) { {product_item_id: product_item.id, rate_card_id: rate_card.id, units: "10"} }

  it "creates a plan product item" do
    expect { result }.to change(PlanProductItem, :count).by(1)

    plan_product_item = result.plan_product_item
    expect(plan_product_item.plan).to eq(plan)
    expect(plan_product_item.product_item).to eq(product_item)
    expect(plan_product_item.rate_card).to eq(rate_card)
    expect(plan_product_item.units).to eq(10)
  end

  it "creates a default rate phase" do
    expect { result }.to change(RatePhase, :count).by(1)

    rate_phase = result.plan_product_item.rate_phases.first
    expect(rate_phase.position).to eq(1)
    expect(rate_phase.billing_interval_cycle_count).to be_nil
    expect(rate_phase.subscription_product_item_id).to be_nil
  end

  context "when the plan is missing" do
    let(:plan) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::NotFoundFailure)
    end
  end

  context "when the product item does not exist" do
    let(:params) { {product_item_id: "unknown", rate_card_id: rate_card.id} }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("product_item")
    end
  end

  context "when the rate card does not exist" do
    let(:params) { {product_item_id: product_item.id, rate_card_id: "unknown"} }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("rate_card")
    end
  end

  context "when the rate card belongs to another product item" do
    let(:other_item) { create(:product_item, organization:) }
    let(:rate_card) { create(:rate_card, organization:, product_item: other_item) }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ValidationFailure)
      expect(result.error.messages[:rate_card_id]).to include("does_not_match_product_item")
    end
  end
end
