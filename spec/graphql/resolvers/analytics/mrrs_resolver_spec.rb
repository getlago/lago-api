# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::Analytics::MrrsResolver do
  let(:required_permission) { "analytics:view" }
  let(:query) do
    <<~GQL
      query($currency: CurrencyEnum, $billingEntityCode: String, $billingEntityId: ID) {
        mrrs(currency: $currency, billingEntityCode: $billingEntityCode, billingEntityId: $billingEntityId) {
          collection {
            month
            amountCents
            currency
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

  context "without premium feature" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:
      )

      expect_graphql_error(
        result:,
        message: "unauthorized"
      )
    end
  end

  context "with premium feature", :premium do
    it "returns a list of mrrs" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:
      )

      mrrs_response = result["data"]["mrrs"]
      month = DateTime.parse mrrs_response["collection"].first["month"]

      expect(month).to eq(DateTime.current.beginning_of_month)
      expect(mrrs_response["collection"].first["amountCents"]).to eq(nil)
      expect(mrrs_response["collection"].first["currency"]).to eq(nil)
    end

    context "when filtering by billing entity code" do
      let(:billing_entity) { create(:billing_entity, organization:, code: "entity_01") }

      it "returns a list of mrrs for the billing entity" do
        result = execute_graphql(
          current_user: membership.user,
          current_organization: organization,
          permissions: required_permission,
          query:,
          variables: {billingEntityCode: billing_entity.code}
        )

        mrrs_response = result["data"]["mrrs"]
        month = DateTime.parse mrrs_response["collection"].first["month"]

        expect(month).to eq(DateTime.current.beginning_of_month)
        expect(mrrs_response["collection"].first["amountCents"]).to eq(nil)
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
end
