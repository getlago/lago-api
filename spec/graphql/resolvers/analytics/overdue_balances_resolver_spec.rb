# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::Analytics::OverdueBalancesResolver do
  let(:required_permission) { "analytics:view" }
  let(:query) do
    <<~GQL
      query($currency: CurrencyEnum, $externalCustomerId: String, $months: Int, $expireCache: Boolean, $billingEntityCode: String, $isCustomerTinEmpty: Boolean) {
        overdueBalances(currency: $currency, externalCustomerId: $externalCustomerId, months: $months, expireCache: $expireCache, billingEntityCode: $billingEntityCode, isCustomerTinEmpty: $isCustomerTinEmpty) {
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

  context "when filtering by customer tax identification number emptiness" do
    let(:customer_without_tin) { create(:customer, organization:, tax_identification_number: nil) }
    let(:customer_with_tin) { create(:customer, organization:, tax_identification_number: "123456789") }

    before do
      create(:invoice, organization:, customer: customer_without_tin, payment_overdue: true,
        payment_due_date: Time.current.beginning_of_month, total_amount_cents: 100)
      create(:invoice, organization:, customer: customer_with_tin, payment_overdue: true,
        payment_due_date: Time.current.beginning_of_month - 1.month, total_amount_cents: 200)
    end

    it "returns overdue balances for customers without a tax identification number" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {isCustomerTinEmpty: true}
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
end
