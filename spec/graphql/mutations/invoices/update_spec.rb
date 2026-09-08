# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Invoices::Update do
  let(:required_permission) { "invoices:update" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:invoice) { create(:invoice, organization:) }
  let(:mutation) do
    <<~GQL
      mutation($input: UpdateInvoiceInput!) {
        updateInvoice(input: $input) {
          id
          paymentStatus
          metadata { id, key, value }
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires permission", "invoices:update"

  it "updates a invoice" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          id: invoice.id,
          paymentStatus: "succeeded",
          metadata: [
            {
              key: "test-key",
              value: "value"
            }
          ]
        }
      }
    )

    result_data = result["data"]["updateInvoice"]

    expect(result_data["id"]).to be_present
    expect(result_data["paymentStatus"]).to eq("succeeded")
    expect(result_data["metadata"][0]["key"]).to eq("test-key")
  end

  context "when invoice does not exists" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {
            id: "1234",
            paymentStatus: "succeeded"
          }
        }
      )

      expect_graphql_error(
        result:,
        message: "Resource not found"
      )
    end
  end

  context "when invoice is voided" do
    let(:invoice) { create(:invoice, :voided, organization:) }

    it "returns a method not allowed error and does not update the invoice" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {
            id: invoice.id,
            paymentStatus: "succeeded"
          }
        }
      )

      expect_graphql_error(
        result:,
        message: "Method Not Allowed"
      )
      expect(result["errors"].first["extensions"]["code"]).to eq("update_on_voided_invoice")
      expect(invoice.reload.payment_status).not_to eq("succeeded")
    end
  end
end
