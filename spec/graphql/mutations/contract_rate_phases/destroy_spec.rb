# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::ContractRatePhases::Destroy do
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
  let(:contract) { create(:contract, :pending, organization:) }
  let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:) }
  let!(:rate_phase) { create(:rate_phase, :contract_level, organization:, contract_rate_card:, position: 1, code: "launch", billing_interval_cycle_count: 3) }

  let(:input) { {contractAppliedRateCardId: contract_rate_card.id, code: "launch"} }

  let(:mutation) do
    <<~GQL
      mutation($input: DestroyContractRatePhaseInput!) {
        destroyContractRatePhase(input: $input) { id code }
      }
    GQL
  end

  before do
    organization.enable_feature_flag!(:product_catalog)
    create(:rate_phase, :contract_level, organization:, contract_rate_card:, position: 2, code: "tail", billing_interval_cycle_count: nil)
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "contracts:update"

  it "removes the phase" do
    expect(execution["data"]["destroyContractRatePhase"]["id"]).to eq(rate_phase.id)
    expect(rate_phase.reload).to be_discarded
  end

  context "when the contract is active" do
    let(:contract) { create(:contract, organization:) }

    it "returns an error" do
      expect_graphql_error(result: execution, message: :unprocessable_entity)
    end
  end
end
