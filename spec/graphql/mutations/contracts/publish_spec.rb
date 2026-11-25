# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Contracts::Publish do
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
  let(:started_at) { 1.month.from_now }
  let(:contract) { create(:contract, :draft, organization:, customer:, catalog_plan:, started_at:) }

  let(:input) { {id: contract.id} }

  let(:mutation) do
    <<-GQL
      mutation($input: PublishContractInput!) {
        publishContract(input: $input) {
          id externalId status
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "contracts:update"

  it "publishes a draft whose start is ahead as pending" do
    expect(execution["data"]["publishContract"]).to include("id" => contract.id, "status" => "pending")
    expect(contract.reload).to be_pending
  end

  context "when the start has passed" do
    let(:started_at) { 1.month.ago }

    it "activates it" do
      expect(execution["data"]["publishContract"]["status"]).to eq("active")
    end
  end

  context "when the contract was canceled" do
    let(:contract) { create(:contract, :canceled, organization:, customer:, catalog_plan:) }

    it "returns a validation error" do
      expect_unprocessable_entity(execution, details: {contract: ["cannot_publish"]})
      expect(contract.reload).to be_canceled
    end
  end

  context "when a pending contract shares its external id" do
    before { create(:contract, :pending, organization:, customer:, external_id: contract.external_id) }

    it "keeps the draft and returns the error on externalId" do
      expect_unprocessable_entity(execution, details: {externalId: ["value_already_exists"]})
      expect(contract.reload).to be_draft
    end
  end

  context "when the contract belongs to another organization" do
    let(:contract) { create(:contract, :draft, started_at:) }

    it "returns a not found error without publishing it" do
      expect_not_found(execution, details: {contract: ["not_found"]})
      expect(contract.reload).to be_draft
    end
  end
end
