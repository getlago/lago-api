# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::ContractAppliedRateCardResolver do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {id: contract_rate_card.id}
    )
  end

  let(:required_permission) { "contracts:view" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:contract) { create(:contract, organization:) }
  let(:contract_rate_card) do
    create(
      :contract_rate_card,
      organization:,
      contract:,
      units: 3,
      effective_date: Date.new(2026, 10, 1),
      billing_anchor_date: Date.new(2026, 10, 15),
      next_billing_at: Time.zone.parse("2026-10-15T00:00:00Z")
    )
  end

  let(:query) do
    <<~GQL
      query($id: ID!) {
        contractAppliedRateCard(id: $id) {
          id units
          effectiveDate billingAnchorDate nextBillingAt
          product { id }
          rateCard { id }
          ratePhases { id rateOverride { id } }
          ratePhasesCount
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "contracts:view"

  it "returns the applied rate card with its dates and rate phases" do
    rate_override = create(:rate_override, organization:)
    rate_phase = create(:rate_phase, :contract_level, organization:, contract_rate_card:, rate_override:)

    expect(execution["data"]["contractAppliedRateCard"]).to eq(
      "id" => contract_rate_card.id,
      "units" => 3.0,
      "effectiveDate" => "2026-10-01",
      "billingAnchorDate" => "2026-10-15",
      "nextBillingAt" => "2026-10-15T00:00:00Z",
      "product" => {"id" => contract_rate_card.rate_card.product_id},
      "rateCard" => {"id" => contract_rate_card.rate_card_id},
      "ratePhases" => [{"id" => rate_phase.id, "rateOverride" => {"id" => rate_override.id}}],
      "ratePhasesCount" => 1
    )
  end

  context "when the applied rate card belongs to another organization" do
    let(:contract_rate_card) { create(:contract_rate_card) }

    it "returns a not found error" do
      expect_graphql_error(result: execution, message: "Resource not found")
    end
  end

  context "when the applied rate card is discarded" do
    let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, deleted_at: Time.current) }

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
