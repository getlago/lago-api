# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::Analytics::OverdueBalancesResolver do
  let(:required_permission) { "analytics:view" }
  let(:query) do
    <<~GQL
      query($currency: CurrencyEnum, $externalCustomerId: String, $months: Int, $expireCache: Boolean, $billingEntityCode: String, $billingEntityId: ID) {
        overdueBalances(currency: $currency, externalCustomerId: $externalCustomerId, months: $months, expireCache: $expireCache, billingEntityCode: $billingEntityCode, billingEntityId: $billingEntityId) {
          collection {
            amountCents
            currency
            lagoInvoiceIds
            month
          }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "analytics:view"

  it "returns a list of overdue balances" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:
    )

    expect(result["data"]["overdueBalances"]["collection"]).to eq([])
  end

  context "when filtering by billing entity code" do
    let(:billing_entity) { create(:billing_entity, organization:, code: "entity_01") }
    let(:customer) { create(:customer, organization:) }

    before do
      create(:invoice, organization:, customer:, billing_entity:, payment_overdue: true,
        payment_due_date: Time.current.beginning_of_month, total_amount_cents: 100)
      create(:invoice, organization:, customer:, billing_entity: organization.default_billing_entity,
        payment_overdue: true, payment_due_date: Time.current.beginning_of_month, total_amount_cents: 200)
    end

    it "returns overdue balances scoped to the billing entity" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {billingEntityCode: billing_entity.code}
      )

      collection = result["data"]["overdueBalances"]["collection"]

      expect(collection.count).to eq(1)
      expect(collection.first["amountCents"]).to eq("100")
    end
  end

  context "when billing entity code does not match any entity of the organization" do
    it "returns a not found error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {billingEntityCode: "unknown"}
      )

      expect_graphql_error(result:, message: "not_found")
    end
  end

  context "when billing entity code belongs to another organization" do
    before { create(:billing_entity, code: "entity_01") }

    it "returns a not found error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {billingEntityCode: "entity_01"}
      )

      expect_graphql_error(result:, message: "not_found")
    end
  end

  context "when billing entity code is blank" do
    it "does not filter by billing entity" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {billingEntityCode: ""}
      )

      expect(result["data"]["overdueBalances"]["collection"]).to eq([])
    end
  end

  context "when both billing entity code and id are provided" do
    let(:billing_entity) { create(:billing_entity, organization:, code: "entity_01") }

    it "returns a validation error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {billingEntityCode: billing_entity.code, billingEntityId: billing_entity.id}
      )

      expect_graphql_error(
        result:,
        message: "unprocessable_entity",
        details: {billingEntityId: ["can't be present when billing_entity_code is provided"]}
      )
    end
  end
end
