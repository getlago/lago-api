# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::ContractResolver do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {contractId: contract.id}
    )
  end

  let(:required_permission) { "contracts:view" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:catalog_plan) { create(:catalog_plan, organization:, code: "premium", currency: "EUR") }
  let(:contract) { create(:contract, organization:, customer:, catalog_plan:) }
  let(:first_card) { create(:contract_rate_card, organization:, contract:) }
  let(:second_card) { create(:contract_rate_card, organization:, contract:, effective_date: 2.days.ago.to_date) }
  let(:first_billing_at) { Time.zone.parse("2026-11-10 12:00:00") }
  let(:second_billing_at) { Time.zone.parse("2026-11-11 12:00:00") }
  let(:first_operation) do
    create(:billing_operation, organization:, customer:, contract_rate_card: first_card,
      billing_at: first_billing_at, target_cycle_started_at: first_billing_at - 1.month)
  end
  let(:second_operation) do
    create(:billing_operation, organization:, customer:, contract_rate_card: second_card,
      billing_at: second_billing_at, target_cycle_started_at: second_billing_at - 1.month)
  end

  let(:query) do
    <<~GQL
      query($contractId: ID!) {
        contract(id: $contractId) {
          id externalId status billingTime
          customer { id }
          plan { id code name currency }
          appliedRateCards { id rateCard { id } effectiveDate nextBillingAt }
          appliedRateCardsCount
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "contracts:view"

  it "returns the contract with its rate cards" do
    card = create(:contract_rate_card, organization:, contract:)

    response = execution["data"]["contract"]

    expect(response["id"]).to eq(contract.id)
    expect(response["customer"]["id"]).to eq(customer.id)
    expect(response["plan"]).to eq(
      "id" => catalog_plan.id,
      "code" => "premium",
      "name" => catalog_plan.name,
      "currency" => "EUR"
    )
    expect(response["appliedRateCards"].sole["id"]).to eq(card.id)
    expect(response["appliedRateCardsCount"]).to eq(1)
  end

  it "loads billing-operation clocks once for its rate-card list" do
    first_operation
    second_operation
    queries = []
    subscriber = ->(*, payload) { queries << payload[:sql] if payload[:sql].include?('FROM "billing_operations"') }

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { execution }

    expect(queries.size).to eq(1)
    expect(queries.sole).to include("GROUP BY")
    expect(execution["data"]["contract"]["appliedRateCards"].map { it["nextBillingAt"] }).to eq(
      [second_billing_at.iso8601, first_billing_at.iso8601]
    )
  end

  # An unpriced card has no billable period, so the nullable field answers null.
  it "answers null for a card whose schedule has run out" do
    create(:contract_rate_card, organization:, contract:)

    expect(execution["data"]["contract"]["appliedRateCards"].sole["nextBillingAt"]).to be_nil
  end

  describe "effectiveBillingAnchorDate" do
    let(:customer) { create(:customer, organization:, timezone: "America/Los_Angeles") }
    let(:contract) { create(:contract, organization:, customer:, catalog_plan:, started_at: Time.zone.parse("2026-10-01T02:00:00Z"), billing_anchor_date:) }
    let(:billing_anchor_date) { nil }
    let(:query) do
      <<~GQL
        query($contractId: ID!) {
          contract(id: $contractId) { billingAnchorDate effectiveBillingAnchorDate }
        }
      GQL
    end

    it "follows the start day in the customer's timezone when no anchor is set" do
      expect(execution["data"]["contract"]).to eq("billingAnchorDate" => nil, "effectiveBillingAnchorDate" => "2026-09-30")
    end

    context "with an anchor set" do
      let(:billing_anchor_date) { Date.new(2026, 10, 15) }

      it "answers the anchor" do
        expect(execution["data"]["contract"]).to eq("billingAnchorDate" => "2026-10-15", "effectiveBillingAnchorDate" => "2026-10-15")
      end
    end
  end

  context "when the contract belongs to another organization" do
    let(:contract) { create(:contract) }

    it "returns a not found error" do
      expect_graphql_error(result: execution, message: "Resource not found")
    end
  end
end
