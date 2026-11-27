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
  let(:customer) { create(:customer, organization:) }
  let(:contract) { create(:contract, organization:, customer:, name: "Platform contract") }
  let(:contract_rate_card) do
    create(
      :contract_rate_card,
      organization:,
      contract:,
      units: 3,
      next_billing_at: Time.zone.parse("2026-10-15T00:00:00Z"),
      effective_date: Date.new(2026, 10, 1),
      billing_anchor_date: Date.new(2026, 10, 15)
    )
  end

  let(:query) do
    <<~GQL
      query($id: ID!) {
        contractAppliedRateCard(id: $id) {
          id units scheduledUnits scheduledUnitsEffectiveAt
          effectiveDate billingAnchorDate nextBillingAt
          contract { id name }
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

  context "with a future draft contract" do
    let(:contract) { create(:contract, :draft, organization:, customer:, started_at: Time.utc(2026, 10, 1)) }

    around { |example| travel_to(Time.utc(2026, 9, 1)) { example.run } }

    it "returns the saved starting units" do
      expect(execution.dig("data", "contractAppliedRateCard", "units")).to eq(3.0)
    end
  end

  context "with a scheduled units change" do
    let(:timestamp) { Time.utc(2026, 11, 15) }

    around { |example| travel_to(timestamp) { example.run } }

    before do
      create(:rate_card_rate, organization:, rate_card: contract_rate_card.rate_card, effective_from: Time.utc(2026, 10, 1))
      contract_rate_card.update!(billing_anchor_date: Date.new(2026, 10, 1))
      create(:contract_rate_card_term, organization:, contract_rate_card:, units: 5, effective_date: Date.new(2026, 11, 15),
        created_at: Time.utc(2026, 11, 15), application_timing: :next_billing_cycle)
    end

    it "returns current units and the scheduled quantity and time" do
      expect(execution.dig("data", "contractAppliedRateCard").slice("units", "scheduledUnits", "scheduledUnitsEffectiveAt"))
        .to eq("units" => 3.0, "scheduledUnits" => 5.0, "scheduledUnitsEffectiveAt" => "2026-12-01T00:00:00Z")
    end

    context "when the scheduled change takes effect" do
      let(:timestamp) { Time.utc(2026, 12, 1) }

      it "returns the new current units without a scheduled change" do
        expect(execution.dig("data", "contractAppliedRateCard").slice("units", "scheduledUnits", "scheduledUnitsEffectiveAt"))
          .to eq("units" => 5.0, "scheduledUnits" => nil, "scheduledUnitsEffectiveAt" => nil)
      end
    end
  end

  context "when the applied rate card has a billing cursor" do
    it "returns the applied rate card with its contract, dates and rate phases" do
      rate_override = create(:rate_override, organization:)
      rate_phase = create(:rate_phase, :contract_level, organization:, contract_rate_card:, rate_override:)

      expect(execution["data"]["contractAppliedRateCard"]).to eq(
        "id" => contract_rate_card.id,
        "units" => 3.0,
        "scheduledUnits" => nil,
        "scheduledUnitsEffectiveAt" => nil,
        "effectiveDate" => "2026-10-01",
        "billingAnchorDate" => "2026-10-15",
        "nextBillingAt" => "2026-10-15T00:00:00Z",
        "contract" => {"id" => contract.id, "name" => "Platform contract"},
        "product" => {"id" => contract_rate_card.rate_card.product_id},
        "rateCard" => {"id" => contract_rate_card.rate_card_id},
        "ratePhases" => [{"id" => rate_phase.id, "rateOverride" => {"id" => rate_override.id}}],
        "ratePhasesCount" => 1
      )
    end

    context "when there are no units rows" do
      let(:contract_rate_card) do
        create(
          :contract_rate_card,
          organization:,
          contract:,
          effective_date: Date.new(2026, 10, 1),
          billing_anchor_date: Date.new(2026, 10, 15)
        )
      end

      it "returns null units" do
        expect(execution.dig("data", "contractAppliedRateCard", "units")).to be_nil
      end
    end

    context "when multiple units rows exist" do
      before do
        create(
          :contract_rate_card_term,
          organization:,
          contract_rate_card:,
          units: 7,
          effective_date: Date.new(2026, 9, 1)
        )
      end

      it "returns the current effective units row" do
        expect(execution.dig("data", "contractAppliedRateCard", "units")).to eq(3.0)
      end
    end
  end

  context "when there are no units rows" do
    let(:contract_rate_card) do
      create(
        :contract_rate_card,
        organization:,
        contract:,
        effective_date: Date.new(2026, 10, 1),
        billing_anchor_date: Date.new(2026, 10, 15),
        next_billing_at: Time.zone.parse("2026-10-15T00:00:00Z")
      )
    end

    it "returns null units" do
      expect(execution.dig("data", "contractAppliedRateCard", "units")).to be_nil
    end
  end

  context "when multiple units rows exist" do
    before do
      create(
        :contract_rate_card_term,
        organization:,
        contract_rate_card:,
        units: 7,
        effective_date: Date.new(2026, 9, 1)
      )
    end

    it "returns the current effective units row" do
      expect(execution.dig("data", "contractAppliedRateCard", "units")).to eq(3.0)
    end
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
