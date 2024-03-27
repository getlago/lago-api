# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::Customers::InvoicesResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query($customerId: ID!) {
        customerInvoices(customerId: $customerId) {
          collection { id }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:, organization:) }
  let(:draft_invoice) { create(:invoice, :draft, customer:, organization:) }
  let(:finalized_invoice) { create(:invoice, customer:, organization:) }

  before do
    subscription
    draft_invoice
    finalized_invoice
  end

  it "returns a list of invoices" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query:,
      variables: {customerId: customer.id}
    )

    invoices_response = result["data"]["customerInvoices"]

    aggregate_failures do
      expect(invoices_response["collection"].count).to eq(customer.invoices.count)
      expect(invoices_response["collection"].pluck("id")).to contain_exactly(draft_invoice.id, finalized_invoice.id)
      expect(invoices_response["metadata"]["currentPage"]).to eq(1)
      expect(invoices_response["metadata"]["totalCount"]).to eq(2)
    end
  end

  context "with filter on status" do
    let(:query) do
      <<~GQL
        query($customerId: ID!, $status: [InvoiceStatusTypeEnum!]) {
          customerInvoices(customerId: $customerId, status: $status) {
            collection { id }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end

    it "only returns draft invoice" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query:,
        variables: {customerId: customer.id, status: ["draft"]}
      )

      invoices_response = result["data"]["customerInvoices"]

      aggregate_failures do
        expect(invoices_response["collection"].count).to eq(1)
        expect(invoices_response["collection"].first["id"]).to eq(draft_invoice.id)
        expect(invoices_response["metadata"]["totalCount"]).to eq(1)
      end
    end
  end

  context "without current organization" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        query:,
        variables: {customerId: customer.id}
      )

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
        query:,
        variables: {customerId: customer.id}
      )

      expect_graphql_error(
        result:,
        message: "Not in organization"
      )
    end
  end

  context "when customer does not exists" do
    it "returns no results" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query:,
        variables: {customerId: "123456"}
      )

      invoices_response = result["data"]["customerInvoices"]

      expect(invoices_response["collection"].count).to eq(0)
    end
  end
end
