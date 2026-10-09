# frozen_string_literal: true

require "rails_helper"

RSpec.describe CatalogPlansQuery do
  subject(:result) { described_class.call(organization:, pagination:, search_term:, filters:) }

  let(:organization) { create(:organization) }
  let(:pagination) { nil }
  let(:search_term) { nil }
  let(:filters) { {} }

  let!(:catalog_plan) { create(:catalog_plan, organization:, name: "Growth", code: "growth") }

  it "returns the organization catalog plans" do
    create(:catalog_plan)

    expect(result).to be_success
    expect(result.catalog_plans).to match_array([catalog_plan])
  end

  # REST no longer renders their count, and GraphQL batches it with its own grouped query.
  context "with an applied rate card" do
    before { create(:plan_rate_card, organization:, catalog_plan:) }

    it "does not preload applied_rate_cards" do
      expect(result.catalog_plans.first.association(:applied_rate_cards)).not_to be_loaded
    end
  end

  context "with a search term" do
    let(:search_term) { "grow" }

    before { create(:catalog_plan, organization:, name: "Other", code: "other") }

    it "filters by name or code" do
      expect(result.catalog_plans).to match_array([catalog_plan])
    end
  end

  context "with rate card filters" do
    let(:product) { create(:product, organization:) }
    let(:product_filter) { create(:product_filter, organization:, product:) }
    let(:filtered_card) { create(:rate_card, organization:, product:, product_filter:) }
    let(:other_card) { create(:rate_card, organization:) }
    let(:other_plan) { create(:catalog_plan, organization:, code: "other") }

    before do
      create(:plan_rate_card, organization:, catalog_plan:, rate_card: filtered_card)
      create(:plan_rate_card, organization:, catalog_plan: other_plan, rate_card: other_card)
    end

    context "with product ids" do
      let(:filters) { {product_ids: [product.id]} }

      it "returns the plans pricing one of those products" do
        expect(result.catalog_plans).to eq([catalog_plan])
      end
    end

    context "with several product ids" do
      let(:filters) { {product_ids: [product.id, other_card.product_id]} }

      it "returns the plans pricing any of them" do
        expect(result.catalog_plans).to match_array([catalog_plan, other_plan])
      end
    end

    context "with ids of another organization" do
      let(:foreign_card) { create(:rate_card) }
      let(:filters) { {rate_card_ids: [foreign_card.id], product_ids: [foreign_card.product_id]} }

      it "returns no plan" do
        expect(result.catalog_plans).to be_empty
      end
    end

    context "with product filter ids" do
      let(:filters) { {product_filter_ids: [product_filter.id]} }

      it "returns the plans pricing one of those filters" do
        expect(result.catalog_plans).to eq([catalog_plan])
      end
    end

    context "with product category ids" do
      let(:filters) { {product_category_ids: [product.product_category_id]} }
      let(:uncategorized_plan) { create(:catalog_plan, organization:, code: "uncategorized") }

      before do
        uncategorized_card = create(:rate_card, organization:, product: create(:product, :standalone, organization:))
        create(:plan_rate_card, organization:, catalog_plan: uncategorized_plan, rate_card: uncategorized_card)
      end

      it "returns the plans pricing a product of those categories" do
        expect(result.catalog_plans).to eq([catalog_plan])
      end
    end

    context "with rate card ids" do
      let(:filters) { {rate_card_ids: [other_card.id]} }

      it "returns the plans holding one of those rate cards" do
        expect(result.catalog_plans).to eq([other_plan])
      end
    end

    context "with filters that only different rate cards match" do
      let(:filters) { {product_filter_ids: [product_filter.id], rate_card_ids: [other_card.id]} }

      before { create(:plan_rate_card, organization:, catalog_plan:, rate_card: other_card) }

      it "requires a single rate card to match them all" do
        expect(result.catalog_plans).to be_empty
      end
    end

    context "with a rate card removed from the plan" do
      let(:removed_card) { create(:rate_card, organization:) }
      let(:filters) { {rate_card_ids: [removed_card.id]} }

      before { create(:plan_rate_card, organization:, catalog_plan:, rate_card: removed_card, deleted_at: Time.current) }

      it "ignores it" do
        expect(result.catalog_plans).to be_empty
      end
    end
  end

  context "with pagination" do
    let(:pagination) { {page: 2, limit: 1} }

    before { create(:catalog_plan, organization:, code: "second") }

    it "paginates the catalog plans" do
      expect(result.catalog_plans.count).to eq(1)
      expect(result.catalog_plans.current_page).to eq(2)
    end
  end
end
