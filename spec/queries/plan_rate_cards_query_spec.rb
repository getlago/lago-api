# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlanRateCardsQuery, type: :query do
  subject(:result) { described_class.call(organization:, pagination:, filters:, order:) }

  let(:organization) { create(:organization) }
  let(:pagination) { nil }
  let(:filters) { {} }
  let(:order) { nil }

  let(:catalog_plan) { create(:catalog_plan, organization:) }
  let!(:plan_rate_card) { create(:plan_rate_card, organization:, catalog_plan:) }
  let!(:other_plan_rate_card) { create(:plan_rate_card, organization:) }

  it "returns all plan products of the organization" do
    expect(result).to be_success
    expect(result.plan_rate_cards).to match_array([plan_rate_card, other_plan_rate_card])
  end

  context "when ordering by product category" do
    let(:order) { :product_category }
    let(:filters) { {plan_id: catalog_plan.id} }
    let(:alpha) { create(:product_category, organization:, name: "Alpha") }
    let(:able) { create(:product, organization:, product_category: alpha, name: "Able") }
    let(:discarded_category) { create(:product_category, organization:, name: "Aaa", deleted_at: Time.current) }

    let(:plan_rate_card) { card_for(create(:product, :standalone, organization:, name: "Aardvark")) }
    let!(:zeta_card) { card_for(create(:product, organization:, product_category: alpha, name: "Zeta")) }
    let!(:able_filter_card) { card_for(able, product_filter: create(:product_filter, organization:, product: able, name: "EU")) }
    let!(:able_card) { card_for(able) }
    let!(:beta_card) { card_for(create(:product, organization:, product_category: create(:product_category, organization:, name: "Beta"))) }
    let!(:discarded_category_card) { card_for(create(:product, organization:, product_category: discarded_category, name: "Beaver")) }

    def card_for(product, product_filter: nil)
      create(:plan_rate_card, organization:, catalog_plan:, rate_card: create(:rate_card, organization:, product:, product_filter:))
    end

    it "groups by category, standalone products last, then by product and filter" do
      expect(result.plan_rate_cards.to_a).to eq(
        [able_card, able_filter_card, zeta_card, beta_card, plan_rate_card, discarded_category_card]
      )
    end
  end

  context "when filtering by plan_id" do
    let(:filters) { {plan_id: catalog_plan.id} }

    it "returns only the plan's products" do
      expect(result.plan_rate_cards).to eq([plan_rate_card])
    end
  end

  context "when filtering by plan_code" do
    let(:filters) { {plan_code: catalog_plan.code} }

    it "returns only the plan's products" do
      expect(result.plan_rate_cards).to eq([plan_rate_card])
    end
  end
end
