# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::InvoiceCreditNotesResolver do
  let_it_be(:plan) { create_default(:plan) }
  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:user) { create_default(:user) }
  let(:required_permission) { "credit_notes:view" }
  let(:organization) { membership.organization }
  let(:invoice) { create(:invoice, customer:, organization:) }
  let(:subscription) { create(:subscription, customer:, organization:) }
  let(:credit_note) { create(:credit_note, organization:, customer:, invoice:) }
  let(:query) do
    <<~GQL
      query($invoiceId: ID!) {
        invoiceCreditNotes(invoiceId: $invoiceId, limit: 5) {
          collection { id }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let_it_be(:membership) { create_default(:membership) }
  let_it_be(:customer) { create_default(:customer, organization:) }

  before do
    subscription
    credit_note
    create(:credit_note, :draft, organization:, customer:, invoice:)
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "credit_notes:view"

  it "returns a list of finalized credit_notes for an invoice" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {
        invoiceId: invoice.id
      }
    )

    credit_notes_response = result["data"]["invoiceCreditNotes"]

    expect(credit_notes_response["collection"].count).to eq(1)
    expect(credit_notes_response["collection"].first["id"]).to eq(credit_note.id)

    expect(credit_notes_response["metadata"]["currentPage"]).to eq(1)
    expect(credit_notes_response["metadata"]["totalCount"]).to eq(1)
  end

  context "when invoice does not exists" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {
          invoiceId: "123456"
        }
      )

      expect_graphql_error(result:, message: "Resource not found")
    end
  end
end
