# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::ContractRatePhases::Create do
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

  let!(:terminal) { create(:rate_phase, :contract_level, organization:, contract_rate_card:, position: 1, billing_interval_cycle_count: nil) }

  let(:input) do
    {contractAppliedRateCardId: contract_rate_card.id, code: "launch", name: "Launch", billingIntervalCycleCount: 3}
  end

  let(:mutation) do
    <<~GQL
      mutation($input: CreateContractRatePhaseInput!) {
        createContractRatePhase(input: $input) {
          id code position name billingIntervalCycleCount rateOverride { rateModel }
        }
      }
    GQL
  end

  before { organization.enable_feature_flag!(:product_catalog) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "contracts:update"

  it "inserts the phase before the indefinite tail" do
    response = execution["data"]["createContractRatePhase"]

    expect(response).to include("code" => "launch", "name" => "Launch", "position" => 1, "billingIntervalCycleCount" => 3)
    expect(terminal.reload.position).to eq(2)
  end

  context "with a rate override" do
    let(:input) do
      {
        contractAppliedRateCardId: contract_rate_card.id,
        code: "overridden",
        billingIntervalCycleCount: 3,
        rateOverride: {rateModel: "standard", rateProperties: {amount: "0"}}
      }
    end

    it "creates the override on the phase" do
      expect(execution["data"]["createContractRatePhase"]["rateOverride"]["rateModel"]).to eq("standard")
    end
  end

  context "when the contract is active" do
    let(:contract) { create(:contract, organization:) }

    it "returns an error" do
      expect_graphql_error(result: execution, message: :unprocessable_entity)
    end
  end

  context "when the rate card belongs to another organization" do
    let(:contract_rate_card) { create(:contract_rate_card, contract: create(:contract, :pending)) }
    let!(:terminal) { nil }

    it "returns a not found error" do
      expect_graphql_error(result: execution, message: "Resource not found")
    end
  end

  context "when the organization is not on the product catalog" do
    before { organization.update!(feature_flags: organization.feature_flags - ["product_catalog"]) }

    it "returns a feature unavailable error" do
      expect(execution["errors"].first.dig("extensions", "code")).to eq("feature_unavailable")
    end
  end
end
