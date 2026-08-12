# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Invoices::Delete do
  let(:required_permission) { "invoices:delete" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, :draft, customer:, organization:) }

  let(:mutation) do
    <<~GQL
      mutation($input: DeleteInvoiceInput!) {
        deleteInvoice(input: $input) {
          id
          status
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "invoices:delete"

  it "marks the draft invoice as deleted" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input: {id: invoice.id}}
    )

    result_data = result["data"]["deleteInvoice"]

    expect(result_data["id"]).to eq(invoice.id)
    expect(result_data["status"]).to eq("deleted")
  end

  context "when the invoice is not a draft" do
    let(:invoice) { create(:invoice, status: :finalized, customer:, organization:) }

    it "returns an error and keeps the invoice" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {input: {id: invoice.id}}
      )

      expect_graphql_error(result:, message: "Method Not Allowed")
      expect(invoice.reload).to be_finalized
    end
  end

  context "when the invoice does not exist" do
    it "returns a not found error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {input: {id: "unknown"}}
      )

      expect_graphql_error(result:, message: "Resource not found")
    end
  end
end
