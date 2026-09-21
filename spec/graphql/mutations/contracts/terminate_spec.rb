# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Contracts::Terminate do
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
  let(:contract) { create(:contract, organization:, customer:, catalog_plan:) }

  let(:input) { {externalId: contract.external_id} }

  let(:mutation) do
    <<-GQL
      mutation($input: TerminateContractInput!) {
        terminateContract(input: $input) {
          id externalId status terminatedAt
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "contracts:update"

  it "terminates the contract" do
    result_data = execution["data"]["terminateContract"]

    expect(result_data["externalId"]).to eq(contract.external_id)
    expect(result_data["status"]).to eq("terminated")
    expect(result_data["terminatedAt"]).to be_present
  end

  context "when the contract is pending" do
    let(:contract) { create(:contract, :pending, organization:, customer:, catalog_plan:) }

    it "cancels it" do
      result_data = execution["data"]["terminateContract"]

      expect(result_data["status"]).to eq("canceled")
    end
  end

  context "when a pending replacement coexists with the active contract" do
    let(:pending_replacement) do
      create(:contract, :pending, organization:, customer:, catalog_plan:, external_id: contract.external_id)
    end

    it "terminates the active contract and leaves the replacement live" do
      pending_replacement

      result_data = execution["data"]["terminateContract"]

      expect(result_data["id"]).to eq(contract.id)
      expect(result_data["status"]).to eq("terminated")
      expect(pending_replacement.reload.status).to eq("pending")
    end
  end

  context "when no live contract matches the external id" do
    let(:contract) { create(:contract, :terminated, organization:, customer:, catalog_plan:) }

    it "returns a not found error" do
      expect_not_found(execution)
    end
  end
end
