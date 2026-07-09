# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::Analytics::GrossRevenuesResolver do
  let(:required_permission) { "analytics:view" }
  let(:query) do
    <<~GQL
      query($currency: CurrencyEnum, $externalCustomerId: String, $expireCache: Boolean, $billingEntityCode: String, $billingEntityId: ID) {
        grossRevenues(currency: $currency, externalCustomerId: $externalCustomerId, expireCache: $expireCache, billingEntityCode: $billingEntityCode, billingEntityId: $billingEntityId) {
          collection {
            month
            amountCents
            currency
            invoicesCount
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

  it "returns a list of gross revenues" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:
    )

    expect(result["data"]["grossRevenues"]["collection"]).to eq([])
  end

  context "when filtering by billing entity code" do
    let(:billing_entity) { create(:billing_entity, organization:, code: "entity_01") }

    it "returns a list of gross revenues for the billing entity" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {billingEntityCode: billing_entity.code}
      )

      expect(result["data"]["grossRevenues"]["collection"]).to eq([])
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
