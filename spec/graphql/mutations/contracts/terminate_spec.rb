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

  let(:required_permission) { "contracts:terminate" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:catalog_plan) { create(:catalog_plan, organization:) }
  let(:contract) { create(:contract, organization:, customer:, catalog_plan:) }

  let(:input) { {id: contract.id} }

  let(:mutation) do
    <<-GQL
      mutation($input: TerminateContractInput!) {
        terminateContract(input: $input) {
          id externalId status terminatedAt canceledAt
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "contracts:terminate"

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

    before { pending_replacement }

    it "terminates the active contract and leaves the replacement live" do
      result_data = execution["data"]["terminateContract"]

      expect(result_data["id"]).to eq(contract.id)
      expect(result_data["status"]).to eq("terminated")
      expect(pending_replacement.reload.status).to eq("pending")
    end

    it "keeps targeting the same contract when termination is retried" do
      expect(execution["data"]["terminateContract"]["id"]).to eq(contract.id)

      retry_execution = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {input:}
      )

      expect_unprocessable_entity(retry_execution, details: {contract: ["cannot_terminate"]})
      expect(contract.reload.status).to eq("terminated")
      expect(pending_replacement.reload.status).to eq("pending")
    end
  end

  %i[terminated canceled].each do |status|
    context "when the selected contract is #{status}" do
      let(:contract) { create(:contract, status, organization:, customer:, catalog_plan:) }
      let(:replacement) { create(:contract, :pending, organization:, customer:, external_id: contract.external_id) }

      before { replacement }

      it "does not terminate the pending replacement instead" do
        expect_unprocessable_entity(execution, details: {contract: ["cannot_terminate"]})
        expect(contract.reload.status).to eq(status.to_s)
        expect(replacement.reload.status).to eq("pending")
      end
    end
  end

  context "when the contract is a draft" do
    let(:contract) { create(:contract, :draft, organization:, customer:, catalog_plan:, started_at: 1.month.ago) }

    it "cancels it" do
      result_data = execution["data"]["terminateContract"]

      expect(result_data).to include("status" => "canceled", "terminatedAt" => nil)
      expect(result_data["canceledAt"]).to be_present
    end
  end

  context "when the contract belongs to another organization" do
    let(:foreign_contract) { create(:contract, external_id: contract.external_id) }
    let(:input) { {id: foreign_contract.id} }

    it "does not terminate either organization's contract" do
      expect_not_found(execution, details: {contract: ["not_found"]})
      expect(foreign_contract.reload.status).to eq("active")
      expect(contract.reload.status).to eq("active")
    end
  end

  context "when the id does not exist" do
    let(:input) { {id: SecureRandom.uuid} }

    it "returns a not found error" do
      expect_not_found(execution, details: {contract: ["not_found"]})
    end
  end

  context "when an external id is sent as the id" do
    let(:input) { {id: contract.external_id} }

    it "does not use an external-id fallback" do
      expect_not_found(execution, details: {contract: ["not_found"]})
      expect(contract.reload.status).to eq("active")
    end
  end

  context "when only externalId is supplied" do
    let(:input) { {externalId: contract.external_id} }

    it "rejects the input without terminating the contract" do
      expect(execution["errors"]).not_to be_empty
      expect(contract.reload.status).to eq("active")
    end
  end

  context "when selecting the pending replacement" do
    let(:contract) { create(:contract, :pending, organization:, customer:, catalog_plan:) }
    let(:active_sibling) { create(:contract, organization:, customer:, external_id: contract.external_id) }

    before { active_sibling }

    it "cancels only the selected pending contract" do
      result_data = execution["data"]["terminateContract"]

      expect(result_data).to include("id" => contract.id, "status" => "canceled")
      expect(active_sibling.reload.status).to eq("active")
    end
  end
end
