# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::Analytics::InvoiceCollectionsResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query($currency: CurrencyEnum) {
        invoiceCollections(currency: $currency) {
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

  context "without premium feature" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
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

    it "returns a list of invoice collections" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query:
      )

      invoice_collections_response = result["data"]["invoiceCollections"]
      month = DateTime.parse invoice_collections_response["collection"].first["month"]

      aggregate_failures do
        expect(month).to eq(DateTime.current.beginning_of_month)
        expect(invoice_collections_response["collection"].first["amountCents"]).to eq("0")
        expect(invoice_collections_response["collection"].first["invoicesCount"]).to eq("0")
      end
    end

    context "without current organization" do
      it "returns an error" do
        result = execute_graphql(current_user: membership.user, query:)

        expect_graphql_error(
          result:,
          message: "Missing organization id"
        )
      end
    end

    context "when not member of the organization" do
      it "returns an error" do
        result = execute_graphql(
          current_user: membership.user,
          current_organization: create(:organization),
          query:
        )

        expect_graphql_error(
          result:,
          message: "Not in organization"
        )
      end
    end

    describe "#resolve" do
      subject(:resolve) { resolver.resolve }

      let(:resolver) { described_class.new(object: nil, context: nil, field: nil) }
      let(:current_organization) { create(:organization) }

      before do
        allow(Analytics::InvoiceCollection).to receive(:find_all_by).and_return([])
        allow(resolver).to receive(:current_organization).and_return(current_organization)
        allow(resolver).to receive(:validate_organization!).and_return(true)

        resolve
      end

      it "calls ::Analytics::InvoiceCollection.find_all_by" do
        expect(Analytics::InvoiceCollection).to have_received(:find_all_by).with(current_organization.id, months: 12)
      end
    end
  end
end
