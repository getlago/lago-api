# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::Analytics::InvoiceCollectionsResolver do
  let(:required_permission) { "analytics:view" }
  let(:query) do
    <<~GQL
      query($currency: CurrencyEnum, $billingEntityCode: String) {
        invoiceCollections(currency: $currency, billingEntityCode: $billingEntityCode) {
          collection {
            month
            amountCents
            invoicesCount
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
    it "returns a list of invoice collections" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:
      )

      invoice_collections_response = result["data"]["invoiceCollections"]
      month = DateTime.parse invoice_collections_response["collection"].first["month"]

      expect(month).to eq(DateTime.current.beginning_of_month)
      expect(invoice_collections_response["collection"].first["amountCents"]).to eq("0")
      expect(invoice_collections_response["collection"].first["invoicesCount"]).to eq("0")
    end

    context "when filtering by billing entity code" do
      let(:billing_entity) { create(:billing_entity, organization:, code: "entity_01") }
      let(:customer) { create(:customer, organization:) }

      before do
        create(:invoice, organization:, customer:, billing_entity:,
          issuing_date: Time.current.beginning_of_month, total_amount_cents: 100)
        create(:invoice, organization:, customer:, billing_entity: organization.default_billing_entity,
          issuing_date: Time.current.beginning_of_month, total_amount_cents: 200)
      end

      it "returns invoice collections scoped to the billing entity" do
        result = execute_graphql(
          current_user: membership.user,
          current_organization: organization,
          permissions: required_permission,
          query:,
          variables: {billingEntityCode: billing_entity.code}
        )

        collection = result["data"]["invoiceCollections"]["collection"]

        expect(collection.count).to eq(1)
        expect(collection.first["amountCents"]).to eq("100")
        expect(collection.first["invoicesCount"]).to eq("1")
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
