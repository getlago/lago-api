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

  context "with an excludePricedOnPlanId filter" do
    let(:query) do
      <<~GQL
        query($planId: ID) {
          rateCards(excludePricedOnPlanId: $planId) { collection { id } }
        }
      GQL
    end

    let(:required_permission) { %w[rate_cards:view plans:view] }
    let(:catalog_plan) { create(:catalog_plan, organization:) }
    let(:variables) { {planId: catalog_plan.id} }

    context "when the plan prices a card" do
      before { create(:plan_rate_card, organization:, catalog_plan:, rate_card: card_one) }

      it "returns the cards the plan can still take" do
        expect(execution["data"]["rateCards"]["collection"].map { it["id"] }).to eq([card_two.id])
      end
    end

    context "without the plans:view permission" do
      let(:required_permission) { "rate_cards:view" }

      it "returns a forbidden error" do
        expect_forbidden_error(execution)
      end
    end

    context "with a plan of another organization" do
      let(:catalog_plan) { create(:catalog_plan, organization: create(:organization)) }

      it "returns a not found error" do
        expect_not_found(execution)
      end
    end
  end

  context "with an excludePricedOnContractId filter" do
    let(:query) do
      <<~GQL
        query($contractId: ID) {
          rateCards(excludePricedOnContractId: $contractId) { collection { id } }
        }
      GQL
    end

    let(:required_permission) { %w[rate_cards:view contracts:view] }
    let(:contract) { create(:contract, customer: create(:customer, organization:)) }
    let(:variables) { {contractId: contract.id} }

    context "when the contract prices a card" do
      before { create(:contract_rate_card, organization:, contract:, rate_card: card_one) }

      it "returns the cards the contract can still take" do
        expect(execution["data"]["rateCards"]["collection"].map { it["id"] }).to eq([card_two.id])
      end
    end

    context "without the contracts:view permission" do
      let(:required_permission) { "rate_cards:view" }

      it "returns a forbidden error" do
        expect_forbidden_error(execution)
      end
    end

    context "with a contract of another organization" do
      let(:contract) { create(:contract, customer: create(:customer, organization: create(:organization))) }

      it "returns a not found error" do
        expect_not_found(execution)
      end
    end
  end
end
