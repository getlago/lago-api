# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::CustomerPortal::InvoicesResolver do
  let(:query) do
    <<~GQL
      query {
        customerPortalInvoices(limit: 5) {
          collection { id }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:draft_invoice) { create(:invoice, :draft, customer:, organization:) }
  let(:finalized_invoice) { create(:invoice, customer:, organization:) }

  before do
    draft_invoice
    finalized_invoice
  end

  it_behaves_like "requires a customer portal user"

  it "returns a list of invoices" do
    result = execute_graphql(
      customer_portal_user: customer,
      query:
    )

    invoices_response = result["data"]["customerPortalInvoices"]

    aggregate_failures do
      expect(invoices_response["collection"].count).to eq(2)
      expect(invoices_response["collection"].pluck("id")).to contain_exactly(draft_invoice.id, finalized_invoice.id)
      expect(invoices_response["metadata"]["currentPage"]).to eq(1)
      expect(invoices_response["metadata"]["totalCount"]).to eq(2)
    end
  end

  context "with filter on status" do
    let(:query) do
      <<~GQL
        query($status: [InvoiceStatusTypeEnum!]) {
          customerPortalInvoices(status: $status) {
            collection { id }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end

    it "only returns draft invoice" do
      result = execute_graphql(
        customer_portal_user: customer,
        query:,
        variables: {status: ["draft"]}
      )

      invoices_response = result["data"]["customerPortalInvoices"]

      aggregate_failures do
        expect(invoices_response["collection"].count).to eq(1)
        expect(invoices_response["collection"].first["id"]).to eq(draft_invoice.id)
        expect(invoices_response["metadata"]["totalCount"]).to eq(1)
      end
    end
  end

  context "without customer portal user" do
    it "returns an error" do
      result = execute_graphql(
        query:
      )

      expect_unauthorized_error(result)
    end
  end
end
