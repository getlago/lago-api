# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::ContractAppliedRateCardsResolver do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables:
    )
  end

  let(:required_permission) { "contracts:view" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:contract) { create(:contract, organization:) }
  let(:variables) { {contractId: contract.id} }
  let!(:contract_rate_card) { create(:contract_rate_card, organization:, contract:) }
  let!(:sibling_card) { create(:contract_rate_card, organization:, contract: create(:contract, organization:)) }

  let(:query) do
    <<~GQL
      query($contractId: ID, $page: Int, $limit: Int) {
        contractAppliedRateCards(contractId: $contractId, page: $page, limit: $limit) {
          collection { id ratePhasesCount product { id } rateCard { id } }
          metadata { currentPage totalCount }
        }
      }
    GQL
  end

  before do
    create(:contract_rate_card)
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "contracts:view"

  it "returns the contract's current rate cards only" do
    response = execution["data"]["contractAppliedRateCards"]

    expect(response["collection"].map { it["id"] }).to eq([contract_rate_card.id])
    expect(response["metadata"]["totalCount"]).to eq(1)
  end

  context "with pagination" do
    let(:variables) { {contractId: contract.id, page: 2, limit: 1} }

    before do
      rate_card = create(:rate_card, organization:, product: contract_rate_card.rate_card.product)
      create(:contract_rate_card, organization:, contract:, rate_card:, effective_date: 10.days.ago.to_date)
    end

    it "returns the requested page, ordered by effective date" do
      response = execution["data"]["contractAppliedRateCards"]

      expect(response["collection"].map { it["id"] }).to eq([contract_rate_card.id])
      expect(response["metadata"]).to eq({"currentPage" => 2, "totalCount" => 2})
    end
  end

  context "with a standalone product starting before a categorized one" do
    let!(:standalone_card) do
      create(
        :contract_rate_card,
        organization:,
        contract:,
        effective_date: 10.days.ago.to_date,
        rate_card: create(:rate_card, organization:, product: create(:product, :standalone, organization:))
      )
    end

    it "groups by category before effective date" do
      ids = execution["data"]["contractAppliedRateCards"]["collection"].map { it["id"] }

      expect(ids).to eq([contract_rate_card.id, standalone_card.id])
    end
  end

  context "with filters" do
    let(:variables) { {contractId: contract.id, productType: "fixed", searchTerm: "fixed_seats"} }
    let!(:fixed_card) do
      create(:contract_rate_card, organization:, contract:, rate_card: create(:rate_card, organization:, product: create(:product, :fixed, organization:), code: "fixed_seats"))
    end

    let(:query) do
      <<~GQL
        query($contractId: ID, $productType: ProductTypeEnum, $searchTerm: String) {
          contractAppliedRateCards(contractId: $contractId, productType: $productType, searchTerm: $searchTerm) {
            collection { id }
          }
        }
      GQL
    end

    it "returns only the matching cards" do
      expect(execution["data"]["contractAppliedRateCards"]["collection"].map { it["id"] }).to eq([fixed_card.id])
    end
  end

  context "without a contract id" do
    let(:variables) { {} }

    it "returns every current rate card of the organization" do
      response = execution["data"]["contractAppliedRateCards"]

      expect(response["collection"].map { it["id"] }).to match_array([contract_rate_card.id, sibling_card.id])
    end
  end
end
