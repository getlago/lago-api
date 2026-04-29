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
          subscription { id }
          number
          orderType
          currentVersion { id version status billingItems content}
          createdAt
          updatedAt
          owners { id email }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:quote) { create(:quote, :with_version, organization:, customer:) }

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

    response = result.dig("data", "quote")

    expect(response.dig("id")).to eq(quote.id)
    expect(response.dig("organization", "id")).to eq(organization.id)
    expect(response.dig("organization", "name")).to eq(organization.name)
    expect(response.dig("subscription", "id")).to eq(quote.subscription_id)
    expect(response.dig("customer", "id")).to eq(customer.id)
    expect(response.dig("customer", "name")).to eq(customer.name)
    expect(response.dig("number")).to eq(quote.number)
    expect(response.dig("orderType")).to eq(quote.order_type)
    expect(response.dig("createdAt")).to eq(quote.created_at.iso8601)
    expect(response.dig("updatedAt")).to eq(quote.updated_at.iso8601)
    expect(response.dig("owners")).to eq([])

    expect(response.dig("currentVersion", "id")).to eq(quote.current_version.id)
    expect(response.dig("currentVersion", "billingItems")).to eq(quote.current_version.billing_items)
    expect(response.dig("currentVersion", "content")).to eq(quote.current_version.content)
    expect(response.dig("currentVersion", "status")).to eq(quote.current_version.status)
    expect(response.dig("currentVersion", "version")).to eq(quote.current_version.version)
  end

  context "when the quote is not found" do
    it "returns a not found error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {
          quoteId: "00000000-0000-0000-0000-000000000000"
        }
      )

      expect_not_found(result)
    end
  end
end
