# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::ContractRatePhases::Update do
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
  let!(:rate_phase) do
    create(:rate_phase, :contract_level, organization:, contract_rate_card:, position: 1, code: "launch", name: "Before", billing_interval_cycle_count: 3)
  end

  let(:input) { {contractAppliedRateCardId: contract_rate_card.id, code: "launch", name: "After", newCode: "intro"} }

  let(:mutation) do
    <<~GQL
      mutation($input: UpdateContractRatePhaseInput!) {
        updateContractRatePhase(input: $input) { id code name }
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

  it "updates the phase addressed by its code" do
    expect(execution["data"]["updateContractRatePhase"]).to include("id" => rate_phase.id, "code" => "intro", "name" => "After")
  end

  context "when the contract is active" do
    let(:contract) { create(:contract, organization:) }

    it "returns an error" do
      expect_graphql_error(result: execution, message: :unprocessable_entity)
    end
  end

  context "when the phase code is unknown" do
    let(:input) { {contractAppliedRateCardId: contract_rate_card.id, code: "unknown", name: "After"} }

    it "returns a not found error" do
      expect_graphql_error(result: execution, message: "Resource not found")
    end
  end
end
