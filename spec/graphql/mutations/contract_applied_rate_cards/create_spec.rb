# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::ContractAppliedRateCards::Create do
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
  let(:rate_card) { create(:rate_card, organization:) }
  # A plan-less contract prices in its customer's currency, so pinning the
  # customer to the card's currency satisfies the service's currency check.
  let(:customer) { create(:customer, organization:, currency: rate_card.currency) }
  let(:contract) { create(:contract, :pending, organization:, customer:, catalog_plan: nil) }

  let(:input) { {externalId: contract.external_id, rateCardCode: rate_card.code, units: 10.0} }

  let(:mutation) do
    <<~GQL
      mutation($input: CreateContractAppliedRateCardInput!) {
        createContractAppliedRateCard(input: $input) {
          id
          units
          ratePhasesCount
          billingAnchorDate
          product { id }
          rateCard { id }
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "contracts:update"

  it "attaches the rate card to the contract with a default rate phase" do
    response = execution["data"]["createContractAppliedRateCard"]

    expect(response["product"]["id"]).to eq(rate_card.product.id)
    expect(response["rateCard"]["id"]).to eq(rate_card.id)
    expect(response["units"]).to eq(10.0)
    expect(response["ratePhasesCount"]).to eq(1)
  end

  context "with nested rate phases" do
    let(:input) do
      {
        externalId: contract.external_id,
        rateCardCode: rate_card.code,
        ratePhases: [
          {code: "launch", position: 1, name: "Launch", billingIntervalCycleCount: 3},
          {code: "standard", position: 2, name: "Standard"}
        ]
      }
    end

    it "creates the card with the provided phases" do
      expect(execution["data"]["createContractAppliedRateCard"]["ratePhasesCount"]).to eq(2)
    end
  end

  context "when a pending replacement coexists with an active contract" do
    let!(:active_contract) do
      create(:contract, organization:, customer:, catalog_plan: nil, external_id: contract.external_id)
    end

    it "attaches the card to the pending contract" do
      response = execution["data"]["createContractAppliedRateCard"]

      expect(ContractRateCard.find(response["id"]).contract).to eq(contract)
      expect(active_contract.applied_rate_cards).to be_empty
    end
  end

  context "when the contract is already active" do
    let(:contract) { create(:contract, organization:, customer:, catalog_plan: nil) }

    it "rejects the attachment as locked" do
      expect_unprocessable_entity(execution, details: {contract: ["contract_locked"]})
    end
  end

  context "when no live contract matches the external id" do
    let(:input) { {externalId: "unknown", rateCardCode: rate_card.code} }

    it "returns a not found error" do
      expect_not_found(execution)
    end
  end

  context "with an explicit billing anchor date" do
    let(:input) { {externalId: contract.external_id, rateCardCode: rate_card.code, billingAnchorDate: "2026-10-01"} }

    it "anchors the card on the provided date" do
      expect(execution["data"]["createContractAppliedRateCard"]["billingAnchorDate"]).to eq("2026-10-01")
    end
  end

  context "with an explicitly empty rate phase list" do
    let(:input) { {externalId: contract.external_id, rateCardCode: rate_card.code, ratePhases: []} }

    it "rejects the attachment" do
      expect_unprocessable_entity(execution)
    end
  end

  context "when the rate card currency differs from the contract's" do
    let(:customer) { create(:customer, organization:, currency: "USD") }

    it "rejects the attachment as a currency mismatch" do
      expect_unprocessable_entity(execution, details: {currency: ["currency_does_not_match"]})
    end
  end

  context "when the organization is not on the product catalog" do
    before { organization.update!(feature_flags: organization.feature_flags - ["product_catalog"]) }

    it "returns a feature unavailable error" do
      expect(execution["errors"].first.dig("extensions", "code")).to eq("feature_unavailable")
    end
  end
end
