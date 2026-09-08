# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::Analytics::MrrsResolver do
  let(:required_permission) { "analytics:view" }
  let(:query) do
    <<~GQL
      query($currency: CurrencyEnum, $billingEntityCode: String) {
        mrrs(currency: $currency, billingEntityCode: $billingEntityCode) {
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
      let(:customer) { create(:customer, organization:) }
      let(:subscription) { create(:subscription, customer:) }
      let(:fee1) { create(:fee, subscription:, amount_cents: 100, amount_currency: "EUR", taxes_amount_cents: 0) }
      let(:fee2) { create(:fee, subscription:, amount_cents: 200, amount_currency: "EUR", taxes_amount_cents: 0) }

      before do
        create(:invoice, organization:, customer:, billing_entity:, status: :finalized,
          issuing_date: Time.current.beginning_of_month, fees: [fee1])
        create(:invoice, organization:, customer:, billing_entity: organization.default_billing_entity,
          status: :finalized, issuing_date: Time.current.beginning_of_month, fees: [fee2])
      end

      it "returns mrrs scoped to the billing entity" do
        result = execute_graphql(
          current_user: membership.user,
          current_organization: organization,
          permissions: required_permission,
          query:,
          variables: {billingEntityCode: billing_entity.code}
        )

        collection = result["data"]["mrrs"]["collection"]
        month = DateTime.parse collection.first["month"]

        expect(collection.count).to eq(1)
        expect(month).to eq(DateTime.current.beginning_of_month)
        expect(collection.first["amountCents"]).to eq("100")
        expect(collection.first["currency"]).to eq("EUR")
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
  end
end
