# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::ContractAppliedRateCards::Update do
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
  let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, units: 5) }
  let(:input) { {id: contract_rate_card.id, units: 20} }

  let(:mutation) do
    <<~GQL
      mutation($input: UpdateContractAppliedRateCardInput!) {
        updateContractAppliedRateCard(input: $input) {
          id
          units
          billingAnchorDate
          nextBillingAt
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "contracts:update"

  it "updates the units" do
    response = execution["data"]["updateContractAppliedRateCard"]

    expect(response["id"]).to eq(contract_rate_card.id)
    expect(response["units"]).to eq(20.0)
    expect(contract_rate_card.reload.units).to eq(20)
  end

  context "when the anchor moves on a card with a rate" do
    let(:contract) do
      create(:contract, :pending, organization:, started_at: Time.zone.parse("2026-11-01"))
    end
    let(:rate_card) { create(:rate_card, organization:) }
    let(:contract_rate_card) do
      create(
        :contract_rate_card,
        organization:,
        contract:,
        rate_card:,
        effective_date: Date.new(2026, 11, 1),
        billing_anchor_date: Date.new(2026, 11, 1),
        next_billing_at: Time.zone.parse("2026-12-01")
      )
    end
    let(:input) { {id: contract_rate_card.id, billingAnchorDate: "2026-11-15"} }

    around { |example| travel_to(Time.zone.parse("2026-09-30T12:00:00Z")) { example.run } }

    before do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2026-09-01"))
      create(:rate_phase, :contract_level, organization:, contract_rate_card:)
    end

    it "moves the anchor and reseeds the billing clock" do
      response = execution["data"]["updateContractAppliedRateCard"]

      expect(response["billingAnchorDate"]).to eq("2026-11-15")
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.zone.parse("2026-11-15"))
    end
  end

  context "when the contract is already active" do
    let(:contract) { create(:contract, organization:) }

    it "rejects the change as locked" do
      expect_unprocessable_entity(execution, details: {contract: ["contract_locked"]})

      expect(contract_rate_card.reload.units).to eq(5)
    end
  end

  context "when the rate card belongs to another organization" do
    let(:contract_rate_card) { create(:contract_rate_card, organization: create(:organization), units: 5) }

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
