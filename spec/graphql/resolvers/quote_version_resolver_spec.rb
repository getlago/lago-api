# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::QuoteVersionResolver do
  let(:required_permission) { "quotes:view" }
  let(:query) do
    <<-GQL
      query($quoteVersionId: ID!) {
        quoteVersion(id: $quoteVersionId) {
          id
          organization { id name }
          quote { id number }
          approvedAt
          billingItems
          content
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
  let(:quote_version) { create(:quote_version, organization:) }

  before do
    quote_version
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "quotes:view"

  it "returns a single quote version" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {
        quoteVersionId: quote_version.id
      }
    )

    response = result.dig("data", "quoteVersion")

    expect(response.dig("id")).to eq(quote_version.id)
    expect(response.dig("organization", "id")).to eq(quote_version.organization.id)
    expect(response.dig("organization", "name")).to eq(quote_version.organization.name)
    expect(response.dig("quote", "id")).to eq(quote_version.quote.id)
    expect(response.dig("quote", "number")).to eq(quote_version.quote.number)
    expect(response.dig("approvedAt")).to eq(quote_version.approved_at&.iso8601)
    expect(response.dig("billingItems")).to eq(quote_version.billing_items)
    expect(response.dig("content")).to eq(quote_version.content)
    expect(response.dig("shareToken")).to eq(quote_version.share_token)
    expect(response.dig("status")).to eq(quote_version.status)
    expect(response.dig("version")).to eq(quote_version.version)
    expect(response.dig("voidReason")).to eq(quote_version.void_reason)
    expect(response.dig("voidedAt")).to eq(quote_version.voided_at&.iso8601)
    expect(response.dig("createdAt")).to eq(quote_version.created_at.iso8601)
    expect(response.dig("updatedAt")).to eq(quote_version.updated_at.iso8601)
  end
end
