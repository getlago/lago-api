# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlanRateCardsQuery, type: :query do
  subject(:result) { described_class.call(organization:, pagination:, filters:, order:, search_term:) }

  let(:organization) { create(:organization) }
  let(:pagination) { nil }
  let(:filters) { {} }
  let(:order) { nil }
  let(:search_term) { nil }

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

  context "with rate card filters" do
    let(:listed_plan) { create(:catalog_plan, organization:) }
    let(:filters) { {plan_id: listed_plan.id}.merge(card_filters) }
    let(:card_filters) { {} }
    let(:category) { create(:product_category, organization:) }
    let(:metered) { create(:product, organization:, product_category: category) }
    let(:product_filter) { create(:product_filter, organization:, product: metered) }

    let!(:metered_card) { listed_card_for(create(:rate_card, organization:, product: metered, name: "Seats monthly")) }
    let!(:filter_card) { listed_card_for(create(:rate_card, organization:, product: metered, product_filter:)) }
    let!(:fixed_card) { listed_card_for(create(:rate_card, organization:, product: create(:product, :fixed, :standalone, organization:))) }

    before do
      create(:rate_phase, organization:, plan_rate_card: fixed_card, rate_override: create(:rate_override, organization:))
      create(:rate_phase, :contract_level, organization:, rate_override: create(:rate_override, organization:))
    end

    def listed_card_for(rate_card)
      create(:plan_rate_card, organization:, catalog_plan: listed_plan, rate_card:)
    end

    context "with products" do
      let(:card_filters) { {product_ids: [metered.id]} }

      it { expect(result.plan_rate_cards).to match_array([metered_card, filter_card]) }
    end

    context "with product filters" do
      let(:card_filters) { {product_filter_ids: [product_filter.id]} }

      it { expect(result.plan_rate_cards).to eq([filter_card]) }
    end

    context "with cards without a product filter" do
      let(:card_filters) { {without_product_filter: true} }

      it { expect(result.plan_rate_cards).to match_array([metered_card, fixed_card]) }
    end

    context "with product filters or none" do
      let(:card_filters) { {product_filter_ids: [product_filter.id], without_product_filter: true} }

      before do
        other_filter = create(:product_filter, organization:, product: metered)
        listed_card_for(create(:rate_card, organization:, product: metered, product_filter: other_filter))
      end

      it { expect(result.plan_rate_cards).to match_array([metered_card, filter_card, fixed_card]) }
    end

    context "with categories" do
      let(:card_filters) { {product_category_ids: [category.id]} }

      it { expect(result.plan_rate_cards).to match_array([metered_card, filter_card]) }
    end

    context "with cards without a category" do
      let(:card_filters) { {without_product_category: true} }

      it { expect(result.plan_rate_cards).to eq([fixed_card]) }
    end

    context "with a product type" do
      let(:card_filters) { {product_type: "fixed"} }

      it { expect(result.plan_rate_cards).to eq([fixed_card]) }
    end

    context "with rate overrides" do
      let(:card_filters) { {has_rate_overrides: true} }

      it { expect(result.plan_rate_cards).to eq([fixed_card]) }
    end

    context "without rate overrides" do
      let(:card_filters) { {has_rate_overrides: false} }

      it { expect(result.plan_rate_cards).to match_array([metered_card, filter_card]) }
    end

    context "with a search term" do
      let(:search_term) { "seats" }

      it { expect(result.plan_rate_cards).to eq([metered_card]) }
    end

    context "with several filters" do
      let(:card_filters) { {product_type: "metered", without_product_filter: true} }

      it { expect(result.plan_rate_cards).to eq([metered_card]) }
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
