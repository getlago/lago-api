# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::ContractAppliedRateCards::Destroy do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input: {id: contract_rate_card.id}}
    )
  end

  let(:required_permission) { "contracts:update" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:contract) { create(:contract, :pending, organization:) }
  let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:) }
  let!(:rate_phase) { create(:rate_phase, organization:, plan_rate_card: nil, contract_rate_card:) }

  let(:mutation) do
    <<~GQL
      mutation($input: DestroyContractAppliedRateCardInput!) {
        destroyContractAppliedRateCard(input: $input) {
          id
          ratePhasesCount
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "contracts:update"

  it "removes the rate card along with its phases" do
    response = execution["data"]["destroyContractAppliedRateCard"]

    expect(response["id"]).to eq(contract_rate_card.id)
    expect(response["ratePhasesCount"]).to eq(0)
    expect(contract_rate_card.reload).to be_discarded
    expect(rate_phase.reload).to be_discarded
  end

  context "when the contract is already active" do
    let(:contract) { create(:contract, organization:) }

    it "rejects the removal as locked" do
      expect_unprocessable_entity(execution, details: {contract: ["contract_locked"]})

      expect(contract_rate_card.reload).not_to be_discarded
    end
  end

  context "when the rate card belongs to another organization" do
    let(:contract_rate_card) { create(:contract_rate_card, organization: create(:organization)) }
    let!(:rate_phase) { nil }

    it "returns a not found error" do
      expect_not_found(execution)
    end
  end

  context "when the organization is not on the product catalog" do
    before { organization.update!(feature_flags: organization.feature_flags - ["product_catalog"]) }

    it "returns a feature unavailable error" do
      expect(execution["errors"].first.dig("extensions", "code")).to eq("feature_unavailable")
    end
  end
end
