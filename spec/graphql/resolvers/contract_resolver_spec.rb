# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::ContractResolver do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {contractId: contract.id}
    )
  end

  let(:required_permission) { "contracts:view" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:catalog_plan) { create(:catalog_plan, organization:, code: "premium", currency: "EUR") }
  let(:contract) { create(:contract, organization:, customer:, catalog_plan:) }

  let(:query) do
    <<~GQL
      query($contractId: ID!) {
        contract(id: $contractId) {
          id externalId status billingTime
          customer { id }
          plan { id code name currency }
          appliedRateCards { id rateCard { id } effectiveDate nextBillingAt }
          appliedRateCardsCount
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "contracts:view"

  it "returns the contract with its rate cards" do
    card = create(:contract_rate_card, organization:, contract:)

    response = execution["data"]["contract"]

    expect(response["id"]).to eq(contract.id)
    expect(response["customer"]["id"]).to eq(customer.id)
    expect(response["plan"]).to eq(
      "id" => catalog_plan.id,
      "code" => "premium",
      "name" => catalog_plan.name,
      "currency" => "EUR"
    )
    expect(response["appliedRateCards"].sole["id"]).to eq(card.id)
    expect(response["appliedRateCardsCount"]).to eq(1)
  end

  context "when the contract belongs to another organization" do
    let(:contract) { create(:contract) }

    it "returns a not found error" do
      expect_graphql_error(result: execution, message: "Resource not found")
    end
  end

  it "returns an exhausted billing clock as null" do
    create(:contract_rate_card, organization:, contract:, next_billing_at: nil)

    expect(execution["errors"]).to be_nil
    expect(execution["data"]["contract"]["appliedRateCards"].sole["nextBillingAt"]).to be_nil
  end
end
