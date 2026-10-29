# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateCardsQuery do
  before_all do
    create_default(:billable_metric)
  end

  subject(:result) { described_class.call(organization:, search_term:, pagination:, filters:) }

  let_it_be(:organization) { create(:organization) }
  let(:search_term) { nil }
  let(:pagination) { nil }
  let(:filters) { {} }

  let(:product) { create(:product, organization:) }
  let!(:card_one) { create(:rate_card, organization:, product:, name: "Growth USD", code: "growth_usd", currency: "USD") }
  let!(:card_two) { create(:rate_card, organization:, name: "Standard EUR", code: "standard_eur", currency: "EUR") }

  it "returns all rate cards of the organization" do
    expect(result.rate_cards).to match_array([card_one, card_two])
  end

  it "does not return rate cards from other organizations" do
    create(:rate_card)
    expect(result.rate_cards).to match_array([card_one, card_two])
  end

  context "with a product_ids filter" do
    let(:filters) { {product_ids: [product.id]} }

    it "returns only the cards of that product" do
      expect(result.rate_cards).to eq([card_one])
    end

    context "with several products" do
      let(:other_product) { create(:product, organization:) }
      let!(:card_three) { create(:rate_card, organization:, product: other_product, code: "extra") }
      let(:filters) { {product_ids: [product.id, other_product.id]} }

      it "returns the cards of all requested products" do
        expect(result.rate_cards).to match_array([card_one, card_three])
      end
    end
  end

  context "with a product_filter_ids filter" do
    let(:item_filter) { create(:product_filter, organization:, product:) }
    let!(:filtered_card) { create(:rate_card, organization:, product:, product_filter: item_filter) }
    let(:filters) { {product_filter_ids: [item_filter.id]} }

    it "returns only the cards of that product filter" do
      expect(result.rate_cards).to eq([filtered_card])
    end

    context "with several product filters" do
      let(:other_filter) { create(:product_filter, organization:, product:, code: "other_filter") }
      let!(:other_filtered_card) { create(:rate_card, organization:, product:, product_filter: other_filter, code: "other_filtered") }
      let(:filters) { {product_filter_ids: [item_filter.id, other_filter.id]} }

      it "returns the cards of all requested product filters" do
        expect(result.rate_cards).to match_array([filtered_card, other_filtered_card])
      end
    end
  end

  # card_one / card_two default products each carry their own category, so they
  # never match these fixtures unless filtered by their own category.
  context "with product_category filters" do
    let(:product_category) { create(:product_category, organization:) }
    let(:categorized_product) { create(:product, organization:, product_category:) }
    let!(:categorized_card) { create(:rate_card, organization:, product: categorized_product, code: "categorized") }
    let!(:standalone_card) { create(:rate_card, organization:, product: create(:product, :standalone, organization:), code: "standalone") }

    context "with product_category_ids" do
      let(:filters) { {product_category_ids: [product_category.id]} }

      it "returns only the cards of products in that category" do
        expect(result.rate_cards).to eq([categorized_card])
      end
    end

    context "with without_product_category" do
      let(:filters) { {without_product_category: true} }

      it "returns only the cards of products with no category" do
        expect(result.rate_cards).to eq([standalone_card])
      end
    end

    context "with both combined" do
      let(:filters) { {product_category_ids: [product_category.id], without_product_category: true} }

      it "returns cards in the category and cards on uncategorized products" do
        expect(result.rate_cards).to match_array([categorized_card, standalone_card])
      end
    end
  end

  context "with a search term" do
    let(:search_term) { "growth" }

    it "returns matching cards" do
      expect(result.rate_cards).to eq([card_one])
    end
  end

  context "with a code filter" do
    let(:filters) { {code: "growth_usd"} }

    it "returns only the card with that code" do
      expect(result.rate_cards).to eq([card_one])
    end
  end

  context "with a currency filter" do
    let(:filters) { {currency: "USD"} }
    let(:pagination) { {page: 1, limit: 1} }

    it "filters before pagination and counts only matching cards" do
      expect(result.rate_cards).to eq([card_one])
      expect(result.rate_cards.total_count).to eq(1)
    end
  end

  context "with a product_code filter" do
    let(:filters) { {product_code: product.code} }

    it "returns only the cards of that product" do
      expect(result.rate_cards).to eq([card_one])
    end
  end

  context "with a product_filter_code filter" do
    let(:item_filter) { create(:product_filter, organization:, product:) }
    let!(:filtered_card) { create(:rate_card, organization:, product:, product_filter: item_filter) }
    let(:filters) { {product_filter_code: item_filter.code} }

    it "returns only the cards of that product filter" do
      expect(result.rate_cards).to eq([filtered_card])
    end
  end

  context "with an exclude_priced_on_plan_id filter" do
    let(:catalog_plan) { create(:catalog_plan, organization:) }
    let(:item_filter) { create(:product_filter, organization:, product:) }
    let!(:filtered_card) { create(:rate_card, organization:, product:, product_filter: item_filter, code: "filtered") }
    let(:priced_card) { create(:rate_card, organization:, product:, code: "priced") }
    let(:filters) { {exclude_priced_on_plan_id: catalog_plan.id} }

    before { create(:plan_rate_card, organization:, catalog_plan:, rate_card: priced_card) }

    it "excludes the cards of the slices the plan prices" do
      expect(result.rate_cards).to match_array([filtered_card, card_two])
    end

    context "when the plan prices a product filter" do
      let(:priced_card) { create(:rate_card, organization:, product:, product_filter: item_filter, code: "priced") }

      it "excludes only the cards of that product filter" do
        expect(result.rate_cards).to match_array([card_one, card_two])
      end
    end

    context "when another plan prices the slice" do
      let(:filters) { {exclude_priced_on_plan_id: create(:catalog_plan, organization:).id} }

      it "excludes no card" do
        expect(result.rate_cards).to match_array([card_one, card_two, filtered_card, priced_card])
      end
    end

    context "when the applied card is deleted" do
      before { PlanRateCard.find_by!(rate_card: priced_card).discard! }

      it "excludes no card" do
        expect(result.rate_cards).to match_array([card_one, card_two, filtered_card, priced_card])
      end
    end

    context "when the plan belongs to another organization" do
      let(:catalog_plan) { create(:catalog_plan, organization: create(:organization)) }

      it "returns a not found error" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.error_code).to eq("plan_not_found")
      end
    end
  end

  context "with an exclude_priced_on_contract_id filter" do
    let(:contract) { create(:contract, customer: create(:customer, organization:)) }
    let(:filters) { {exclude_priced_on_contract_id: contract.id} }

    before { create(:contract_rate_card, organization:, contract:, rate_card: create(:rate_card, organization:, product:, code: "priced")) }

    it "excludes the cards of the slices the contract prices" do
      expect(result.rate_cards).to eq([card_two])
    end

    context "when the contract belongs to another organization" do
      let(:contract) { create(:contract, customer: create(:customer, organization: create(:organization))) }

      it "returns a not found error" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.error_code).to eq("contract_not_found")
      end
    end
  end

  context "with pagination" do
    let(:pagination) { {page: 1, limit: 1} }

    it "paginates the results" do
      expect(result.rate_cards.count).to eq(1)
      expect(result.rate_cards.total_count).to eq(2)
    end
  end
end
