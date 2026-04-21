# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::QuotesResolver do
  let(:required_permission) { "quotes:view" }
  let(:query) do
    <<~GQL
      query {
        quotes(limit: 5) {
          collection { id number version }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:membership) { create(:membership, organization:) }

  before do
    (1..5).each do |version|
      create(
        :quote,
        organization:,
        customer:,
        sequential_id: 1,
        number: "QT-2025-0001",
        status: :voided,
        version:
      )
    end
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "quotes:view"

  it "returns a paginated list of quotes ordered by number and version" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:
    )

    quotes_response = result["data"]["quotes"]
    expect(quotes_response["collection"].count).to eq(5)
    expect(quotes_response["metadata"]["currentPage"]).to eq(1)
    expect(quotes_response["metadata"]["totalCount"]).to eq(5)

    first_quote = quotes_response["collection"].first
    expect(first_quote["number"]).to eq("QT-2025-0001")
    expect(first_quote["version"]).to eq(5)

    last_quote = quotes_response["collection"].last
    expect(last_quote["number"]).to eq("QT-2025-0001")
    expect(last_quote["version"]).to eq(1)
  end

  context "when quotes exist in another organization" do
    let(:other_organization) { create(:organization) }
    let(:other_customer) { create(:customer, organization: other_organization) }

    before do
      create(:quote, organization: other_organization, customer: other_customer, sequential_id: 1, number: "QT-2025-0099")
    end

    it "does not return quotes from other organizations" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:
      )

      quotes_response = result["data"]["quotes"]
      expect(quotes_response["collection"].count).to eq(5)
      expect(quotes_response["metadata"]["totalCount"]).to eq(5)
    end
  end
end
