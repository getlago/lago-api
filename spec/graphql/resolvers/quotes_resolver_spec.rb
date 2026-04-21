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

  context "when filtering by customer" do
    let(:other_customer) { create(:customer, organization:) }
    let(:query) do
      <<~GQL
        query($customer: [ID!]) {
          quotes(limit: 5, customer: $customer) {
            collection { id }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end

    before do
      create(:quote, organization:, customer: other_customer, sequential_id: 2, number: "QT-2025-0002")
    end

    it "returns only quotes for the passed customer" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {customer: [customer.id]}
      )

      quotes_response = result["data"]["quotes"]
      expect(quotes_response["metadata"]["totalCount"]).to eq(5)
    end

    context "when the filter targets a customer from another organization" do
      let(:other_organization) { create(:organization) }
      let(:foreign_customer) { create(:customer, organization: other_organization) }

      before do
        create(:quote, organization: other_organization, customer: foreign_customer, sequential_id: 1, number: "QT-2025-0099")
      end

      it "does not leak quotes from other organizations" do
        result = execute_graphql(
          current_user: membership.user,
          current_organization: organization,
          permissions: required_permission,
          query:,
          variables: {customer: [foreign_customer.id]}
        )

        quotes_response = result["data"]["quotes"]
        expect(quotes_response["collection"]).to be_empty
        expect(quotes_response["metadata"]["totalCount"]).to eq(0)
      end
    end
  end

  context "when filtering by status" do
    let(:query) do
      <<~GQL
        query {
          quotes(limit: 5, status: [draft]) {
            collection { id }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end

    let!(:draft_quote) do
      create(:quote, organization:, customer:, sequential_id: 2, number: "QT-2025-0002", status: :draft)
    end

    it "returns only quotes with the passed status" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:
      )

      quotes_response = result["data"]["quotes"]
      expect(quotes_response["collection"].count).to eq(1)
      expect(quotes_response["collection"].first["id"]).to eq(draft_quote.id)
    end
  end

  context "when filtering by number" do
    let(:query) do
      <<~GQL
        query {
          quotes(limit: 5, number: ["QT-2025-0002"]) {
            collection { id }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end

    let!(:other_quote) do
      create(:quote, organization:, customer:, sequential_id: 2, number: "QT-2025-0002")
    end

    it "returns only quotes matching the numbers" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:
      )

      quotes_response = result["data"]["quotes"]
      expect(quotes_response["collection"].count).to eq(1)
      expect(quotes_response["collection"].first["id"]).to eq(other_quote.id)
    end
  end

  context "when filtering by version" do
    let(:query) do
      <<~GQL
        query {
          quotes(limit: 5, version: [5]) {
            collection { id version }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end

    it "returns only quotes at the passed versions" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:
      )

      quotes_response = result["data"]["quotes"]
      expect(quotes_response["collection"].count).to eq(1)
      expect(quotes_response["collection"].first["version"]).to eq(5)
    end
  end

  context "when filtering by date window" do
    let(:query) do
      <<~GQL
        query($fromDate: ISO8601Date, $toDate: ISO8601Date) {
          quotes(limit: 5, fromDate: $fromDate, toDate: $toDate) {
            collection { id }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end

    it "returns quotes created within the window" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {fromDate: Date.yesterday.iso8601, toDate: Date.tomorrow.iso8601}
      )

      quotes_response = result["data"]["quotes"]
      expect(quotes_response["metadata"]["totalCount"]).to eq(5)
    end
  end

  context "when filtering by owners" do
    let(:query) do
      <<~GQL
        query($owners: [ID!]) {
          quotes(limit: 5, owners: $owners) {
            collection { id }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end

    let(:owner_user) { create(:user) }
    let(:owned_quote) do
      create(:quote, organization:, customer:, sequential_id: 2, number: "QT-2025-0002")
    end

    before do
      create(:quote_owner, organization:, quote: owned_quote, user: owner_user)
    end

    it "returns only quotes with the matching owners" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {owners: [owner_user.id]}
      )

      quotes_response = result["data"]["quotes"]
      expect(quotes_response["collection"].count).to eq(1)
      expect(quotes_response["collection"].first["id"]).to eq(owned_quote.id)
    end
  end

  context "when filtering by latest_version_only" do
    let(:query) do
      <<~GQL
        query {
          quotes(limit: 5, latestVersionOnly: true) {
            collection { id version }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end

    it "returns only the highest version per sequential_id" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:
      )

      quotes_response = result["data"]["quotes"]
      expect(quotes_response["collection"].count).to eq(1)
      expect(quotes_response["collection"].first["version"]).to eq(5)
    end
  end
end
