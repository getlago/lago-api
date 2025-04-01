# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::Analytics::DraftInvoicesCollectionsResolver, type: :graphql do
  let(:required_permission) { "analytics:view" }
  let(:query) do
    <<~GQL
      query($currency: CurrencyEnum) {
        draftInvoicesCollections(currency: $currency) {
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

  context "with premium feature" do
    around { |test| lago_premium!(&test) }

    it "returns a list of draft invoices collections" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:
      )

      draft_invoices_collections_response = result["data"]["draftInvoicesCollections"]
      month = DateTime.parse draft_invoices_collections_response["collection"].first["month"]

      aggregate_failures do
        expect(month).to eq(DateTime.current.beginning_of_month)
        expect(draft_invoices_collections_response["collection"].first["amountCents"]).to eq("0")
        expect(draft_invoices_collections_response["collection"].first["invoicesCount"]).to eq("0")
      end
    end
  end
end
