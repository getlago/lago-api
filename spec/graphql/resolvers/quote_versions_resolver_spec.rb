# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::QuoteVersionsResolver do
  let(:required_permission) { "quotes:view" }
  let(:query) do
    <<~GQL
      query {
        quoteVersions(limit: 5) {
          collection { id version }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:membership) { create(:membership, organization:) }
  let(:quote) { create(:quote, organization:, customer:) }

  before do
    (1..3).each do |version|
      create(
        :quote_version,
        :voided,
        quote:,
        organization:
      )
    end
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "quotes:view"

  context "when all versions are requested" do
    it "returns a full list of quote versions" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:
      )

      response = result.dig("data", "quoteVersions")
      expect(response.dig("collection").count).to eq(3)
      expect(response.dig("metadata", "currentPage")).to eq(1)
      expect(response.dig("metadata", "totalCount")).to eq(3)
    end
  end

  context "when filtering by customer" do
    let(:other_customer) { create(:customer, organization:) }
    let!(:other_quote) { create(:quote, :with_version, organization:, customer: other_customer) }
    let(:other_quote_version) { other_quote.current_version }

    let(:query) do
      <<~GQL
        query {
          quoteVersions(limit: 5, customers: ["#{other_customer.id}"]) {
            collection { id quote { customer { id } } }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end

    it "returns quote versions for the specified customer" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:
      )

      response = result.dig("data", "quoteVersions")
      expect(response.dig("collection").count).to eq(1)
      expect(response.dig("collection").first.dig("id")).to eq(other_quote_version.id)
      expect(response.dig("collection").first.dig("quote", "customer", "id")).to eq(other_customer.id)
      expect(response.dig("metadata", "totalCount")).to eq(1)
    end
  end

  context "when filtering by number" do
    let!(:other_quote) { create(:quote, :with_version, organization:, customer:, sequential_id: 99999) }
    let(:other_quote_version) { other_quote.current_version }

    let(:query) do
      <<~GQL
        query {
          quoteVersions(limit: 5, numbers: ["#{other_quote.number}"]) {
            collection { id quote { number } }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end

    it "returns quote versions with the given number" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:
      )

      response = result.dig("data", "quoteVersions")
      expect(response.dig("collection").count).to eq(1)
      expect(response.dig("collection").first.dig("id")).to eq(other_quote_version.id)
      expect(response.dig("collection").first.dig("quote", "number")).to eq(other_quote.number)
    end
  end

  context "when filtering by status" do
    let!(:approved_quote_version) { create(:quote_version, :approved, organization:) }

    let(:query) do
      <<~GQL
        query {
          quoteVersions(limit: 5, statuses: [approved]) {
            collection { id }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end

    it "returns quote versions with the specified version status" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:
      )

      response = result.dig("data", "quoteVersions")
      expect(response.dig("collection").count).to eq(1)
      expect(response.dig("collection").first.dig("id")).to eq(approved_quote_version.id)
      expect(response.dig("metadata", "totalCount")).to eq(1)
    end
  end

  context "when filtering by from_date and to_date" do
    let!(:old_quote_version) { create(:quote_version, organization:, created_at: 10.days.ago) }

    let(:query) do
      <<~GQL
        query {
          quoteVersions(limit: 5, fromDate: "#{11.days.ago.iso8601}", toDate: "#{9.days.ago.iso8601}") {
            collection { id }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end

    it "returns quote versions created within the provided date range" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:
      )

      response = result.dig("data", "quoteVersions")
      expect(response.dig("collection").count).to eq(1)
      expect(response.dig("collection").first.dig("id")).to eq(old_quote_version.id)
      expect(response.dig("metadata", "totalCount")).to eq(1)
    end
  end

  context "when filtering by owners" do
    let(:owner_user) { membership.user }
    let(:query) do
      <<~GQL
        query {
          quoteVersions(limit: 5, owners: ["#{owner_user.id}"]) {
            collection { id }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end
    let!(:owner_quote) { create(:quote, :with_version, organization:, customer:) }
    let(:owner_quote_version) { owner_quote.current_version }

    before do
      QuoteOwner.create!(organization:, quote: owner_quote, user: owner_user)
    end

    it "returns quote versions that belong to the specified owners" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:
      )

      response = result.dig("data", "quoteVersions")
      expect(response.dig("collection").count).to eq(1)
      expect(response.dig("collection").first.dig("id")).to eq(owner_quote_version.id)
      expect(response.dig("metadata", "totalCount")).to eq(1)
    end
  end
end
