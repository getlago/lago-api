# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::QuoteResolver do
  let(:required_permission) { "quotes:view" }
  let(:query) do
    <<~GQL
      query($quoteId: ID!) {
        quote(id: $quoteId) {
          id
          customer { id name }
          organization { id name }
          subscription { id }
          owners { id email }
          number
          orderType
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
  let(:owners) { create_list(:membership, 2, organization:).map(&:user) }

  before do
    owners.each { |u| create(:quote_owner, organization:, quote:, user: u) }
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
    expect(quote_response["subscription"]).to be_nil
    expect(quote_response["owners"]).to match_array(
      owners.map { |u| {"id" => u.id, "email" => u.email} }
    )
    expect(quote_response["number"]).to eq(quote.number)
    expect(quote_response["orderType"]).to eq(quote.order_type)
    expect(quote_response["status"]).to eq(quote.status)
    expect(quote_response["version"]).to eq(quote.version)
    expect(quote_response["voidReason"]).to be_nil
    expect(quote_response["voidedAt"]).to be_nil
    expect(quote_response["createdAt"]).to eq(quote.created_at.iso8601)
    expect(quote_response["updatedAt"]).to eq(quote.updated_at.iso8601)
  end

  context "when quote is not found" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {
          quoteId: SecureRandom.uuid
        }
      )

      expect_graphql_error(result:, message: "Resource not found")
    end
  end

  context "when quote belongs to another organization" do
    let(:other_organization) { create(:organization) }
    let(:other_customer) { create(:customer, organization: other_organization) }
    let(:other_quote) { create(:quote, organization: other_organization, customer: other_customer) }

    it "returns a not found error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {
          quoteId: other_quote.id
        }
      )

      expect_graphql_error(result:, message: "Resource not found")
    end
  end
end
