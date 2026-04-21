# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::QuoteResolver do
  let(:required_permission) { "quotes:view" }
  let(:query) do
    <<-GQL
      query($quoteId: ID!) {
        quote(id: $quoteId) {
          id
          customer { id name }
          organization { id name }
          approvedAt
          autoExecute
          backdatedBilling
          billingItems
          commercialTerms
          contacts
          content
          currency
          description
          executionMode
          internalNotes
          legalText
          metadata
          number
          orderType
          shareToken
          status
          version
          voidReason
          voidedAt
          createdAt
          updatedAt
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:quote) { create(:quote, organization:, customer:) }

  before do
    quote
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "quotes:view"

  it "returns a single quote" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {
        quoteId: quote.id
      }
    )

    quote_response = result["data"]["quote"]

    expect(quote_response["id"]).to eq(quote.id)
    expect(quote_response["organization"]["id"]).to eq(organization.id)
    expect(quote_response["organization"]["name"]).to eq(organization.name)
    expect(quote_response["customer"]["id"]).to eq(customer.id)
    expect(quote_response["customer"]["name"]).to eq(customer.name)
    expect(quote_response["approvedAt"]).to eq(quote.approved_at&.iso8601)
    expect(quote_response["autoExecute"]).to eq(quote.auto_execute)
    expect(quote_response["backdatedBilling"]).to eq(quote.backdated_billing)
    expect(quote_response["billingItems"]).to eq(quote.billing_items)
    expect(quote_response["commercialTerms"]).to eq(quote.commercial_terms)
    expect(quote_response["contacts"]).to eq(quote.contacts)
    expect(quote_response["content"]).to eq(quote.content)
    expect(quote_response["currency"]).to eq(quote.currency)
    expect(quote_response["description"]).to eq(quote.description)
    expect(quote_response["executionMode"]).to eq(quote.execution_mode)
    expect(quote_response["internalNotes"]).to eq(quote.internal_notes)
    expect(quote_response["legalText"]).to eq(quote.legal_text)
    expect(quote_response["metadata"]).to eq(quote.metadata)
    expect(quote_response["number"]).to eq(quote.number)
    expect(quote_response["orderType"]).to eq(quote.order_type)
    expect(quote_response["shareToken"]).to eq(quote.share_token)
    expect(quote_response["status"]).to eq(quote.status)
    expect(quote_response["version"]).to eq(quote.version)
    expect(quote_response["voidReason"]).to eq(quote.void_reason)
    expect(quote_response["voidedAt"]).to eq(quote.voided_at&.iso8601)
    expect(quote_response["createdAt"]).to eq(quote.created_at.iso8601)
    expect(quote_response["updatedAt"]).to eq(quote.updated_at.iso8601)
  end
end
