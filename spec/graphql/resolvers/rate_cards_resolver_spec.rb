# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::RateCardsResolver do
  let_it_be(:billable_metric) { create_default(:billable_metric) }
  let_it_be(:organization, refind: true) { create_default(:organization) }
  let_it_be(:user) { create_default(:user) }
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables:
    )
  end

  let(:required_permission) { "rate_cards:view" }
  let(:organization) { membership.organization }
  let(:variables) { {} }
  let(:query) do
    <<~GQL
      query($searchTerm: String, $productIds: [ID!], $productCategoryIds: [ID!], $withoutProductCategory: Boolean, $currency: CurrencyEnum) {
        rateCards(limit: 5, searchTerm: $searchTerm, productIds: $productIds, productCategoryIds: $productCategoryIds, withoutProductCategory: $withoutProductCategory, currency: $currency) {
          collection { id name code currency }
          metadata { currentPage totalCount }
        }
      }
    GQL
  end

  let(:product_category) { create(:product_category, organization:) }
  let(:product) { create(:product, organization:, product_category:) }
  let!(:card_one) { create(:rate_card, organization:, product:, name: "Growth USD", code: "growth_usd", currency: "USD") }
  let!(:card_two) { create(:rate_card, organization:, name: "Standard EUR", code: "standard_eur", currency: "EUR") }

  let_it_be(:membership, refind: true) { create_default(:membership) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "rate_cards:view"

  it "returns the rate cards of the organization" do
    response = execution["data"]["rateCards"]

    expect(response["collection"].map { it["id"] }).to match_array([card_one.id, card_two.id])
    expect(response["metadata"]["totalCount"]).to eq(2)
  end

  context "with a productIds filter" do
    let(:variables) { {productIds: [product.id]} }

    it "returns only the cards of those items" do
      expect(execution["data"]["rateCards"]["collection"].map { it["id"] }).to eq([card_one.id])
    end
  end

  context "with a productCategoryIds filter" do
    let(:variables) { {productCategoryIds: [product_category.id]} }

    it "returns only the cards of products in that category" do
      expect(execution["data"]["rateCards"]["collection"].map { it["id"] }).to eq([card_one.id])
    end
  end

  context "with a withoutProductCategory filter" do
    # card_one and card_two are on products that each carry a category.
    let!(:standalone_card) { create(:rate_card, organization:, product: create(:product, :standalone, organization:), code: "standalone") }
    let(:variables) { {withoutProductCategory: true} }

    it "returns only the cards of uncategorized products" do
      expect(execution["data"]["rateCards"]["collection"].map { it["id"] }).to eq([standalone_card.id])
    end
  end

  context "with a search term" do
    let(:variables) { {searchTerm: "growth"} }

    it "returns matching cards" do
      expect(execution["data"]["rateCards"]["collection"].map { it["id"] }).to eq([card_one.id])
    end
  end

  context "with a currency filter" do
    let(:variables) { {currency: "USD"} }

    before do
      5.times { |index| create(:rate_card, organization:, currency: "EUR", code: "other_eur_#{index}") }
    end

    it "filters before pagination and counts only matching cards" do
      response = execution["data"]["rateCards"]

      expect(response["collection"].map { it["id"] }).to eq([card_one.id])
      expect(response["metadata"]["totalCount"]).to eq(1)
    end
  end

  describe "alreadyPriced" do
    let(:query) do
      <<~GQL
        query($planId: ID, $contractId: ID) {
          rateCards(limit: 20) {
            collection { id alreadyPriced(planId: $planId, contractId: $contractId) }
          }
        }
      GQL
    end

    let(:required_permission) { %w[rate_cards:view plans:view contracts:view] }
    let(:product_filter) { create(:product_filter, organization:, product:) }
    let!(:filtered_card) { create(:rate_card, organization:, product:, product_filter:, code: "filtered_usd") }
    let(:catalog_plan) { create(:catalog_plan, organization:) }
    let(:contract) { create(:contract, organization:, customer: create(:customer, organization:)) }
    let(:already_priced) { execution["data"]["rateCards"]["collection"].to_h { [it["id"], it["alreadyPriced"]] } }

    # Priced through another card of the same slice: the flag follows the slice, not the card.
    def price_slice(owner, product_filter: nil)
      rate_card = create(:rate_card, organization:, product:, product_filter:)

      if owner.is_a?(CatalogPlan)
        create(:plan_rate_card, organization:, catalog_plan: owner, rate_card:)
      else
        create(:contract_rate_card, organization:, contract: owner, rate_card:)
      end
    end

    context "with a planId" do
      let(:variables) { {planId: catalog_plan.id} }

      it "flags the cards of the slice the plan prices without a filter" do
        price_slice(catalog_plan)

        expect(already_priced).to include(card_one.id => true, filtered_card.id => false, card_two.id => false)
      end

      it "flags the cards of the filter slice the plan prices" do
        price_slice(catalog_plan, product_filter:)

        expect(already_priced).to include(card_one.id => false, filtered_card.id => true, card_two.id => false)
      end

      it "ignores the slices priced on another plan" do
        price_slice(create(:catalog_plan, organization:))

        expect(already_priced).to include(card_one.id => false, filtered_card.id => false)
      end

      it "loads the priced slices once for the whole page" do
        price_slice(catalog_plan)

        statements = capture_sql { execution }

        expect(statements.count { it.include?('FROM "plan_rate_cards"') }).to eq(1)
      end
    end

    context "with a contractId" do
      let(:variables) { {contractId: contract.id} }

      it "flags the cards of the slice the contract prices without a filter" do
        price_slice(contract)

        expect(already_priced).to include(card_one.id => true, filtered_card.id => false, card_two.id => false)
      end

      it "flags the cards of the filter slice the contract prices" do
        price_slice(contract, product_filter:)

        expect(already_priced).to include(card_one.id => false, filtered_card.id => true)
      end

      it "ignores the slices priced on another contract" do
        price_slice(create(:contract, organization:, customer: create(:customer, organization:)))

        expect(already_priced).to include(card_one.id => false, filtered_card.id => false)
      end
    end

    context "with a plan of another organization" do
      let(:other_plan) { create(:catalog_plan, organization: create(:organization)) }
      let(:variables) { {planId: other_plan.id} }

      it "flags no card" do
        price_slice(other_plan)

        expect(already_priced.values).to all(be(false))
      end
    end

    context "with a contract of another organization" do
      let(:other_organization) { create(:organization) }
      let(:other_contract) { create(:contract, organization: other_organization, customer: create(:customer, organization: other_organization)) }
      let(:variables) { {contractId: other_contract.id} }

      it "flags no card" do
        price_slice(other_contract)

        expect(already_priced.values).to all(be(false))
      end
    end

    context "with a planId but without the plans:view permission" do
      let(:required_permission) { %w[rate_cards:view contracts:view] }
      let(:variables) { {planId: catalog_plan.id} }

      it "answers nothing" do
        price_slice(catalog_plan)

        expect(already_priced.values).to all(be_nil)
      end
    end

    context "with a contractId but without the contracts:view permission" do
      let(:required_permission) { %w[rate_cards:view plans:view] }
      let(:variables) { {contractId: contract.id} }

      it "answers nothing" do
        price_slice(contract)

        expect(already_priced.values).to all(be_nil)
      end
    end

    context "with both a planId and a contractId" do
      let(:variables) { {planId: catalog_plan.id, contractId: contract.id} }

      it "returns an error" do
        expect_graphql_error(result: execution, message: "alreadyPriced must include exactly one of the following arguments: planId, contractId.")
      end
    end

    context "without a planId or a contractId" do
      it "returns an error" do
        expect_graphql_error(result: execution, message: "alreadyPriced must include exactly one of the following arguments: planId, contractId.")
      end
    end
  end
end
