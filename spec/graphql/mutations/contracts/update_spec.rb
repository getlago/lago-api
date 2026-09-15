# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Contracts::Update do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input:}
    )
  end

  let(:required_permission) { "contracts:update" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:catalog_plan) { create(:catalog_plan, organization:) }
  let(:contract) { create(:contract, :pending, organization:, customer:, catalog_plan:) }

  let(:input) { {externalId: contract.external_id, name: "Renamed"} }

  let(:mutation) do
    <<-GQL
      mutation($input: UpdateContractInput!) {
        updateContract(input: $input) {
          id externalId name
          plan { id }
          appliedRateCards { id }
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "contracts:update"

  it "updates the contract" do
    result_data = execution["data"]["updateContract"]

    expect(result_data["externalId"]).to eq(contract.external_id)
    expect(result_data["name"]).to eq("Renamed")
  end

  context "when changing the plan" do
    let(:other_plan) { create(:catalog_plan, organization:) }
    let(:input) { {externalId: contract.external_id, planCode: other_plan.code} }

    it "re-materializes the rate cards from the new plan" do
      create(:plan_rate_card, organization:, catalog_plan: other_plan, rate_card: create(:rate_card, organization:))

      result_data = execution["data"]["updateContract"]

      expect(result_data["plan"]["id"]).to eq(other_plan.id)
      expect(result_data["appliedRateCards"].size).to eq(1)
    end
  end

  context "when the contract is already active" do
    let(:contract) { create(:contract, organization:, customer:, catalog_plan:) }

    it "returns a validation error" do
      expect_unprocessable_entity(execution)
    end
  end
end
