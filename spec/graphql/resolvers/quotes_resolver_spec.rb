# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::QuotesResolver do
  let(:required_permission) { "quotes:view" }
  let(:query) do
    <<~GQL
      query {
        quotes(limit: 5) {
          collection { id number }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:membership) { create(:membership, organization:) }

  before do
    (1..3).each do |version|
      create(
        :quote,
        organization:,
        customer:
      )
    end
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "quotes:view"

  context "when all versions are requested" do
    it "returns a full list of quotes" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:
      )

      response = result.dig("data", "quotes")
      expect(response.dig("collection").count).to eq(3)
      expect(response.dig("metadata", "currentPage")).to eq(1)
      expect(response.dig("metadata", "totalCount")).to eq(3)
    end
  end

  context "when filtering by customer" do
    let(:other_customer) { create(:customer, organization:) }
    let!(:other_quote) { create(:quote, organization:, customer: other_customer) }

    let(:query) do
      <<~GQL
        query {
          quotes(limit: 5, customers: ["#{other_customer.id}"]) {
            collection { id }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end

    it "returns quotes for the specified customer" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:
      )

      response = result.dig("data", "quotes")
      expect(response.dig("collection").count).to eq(1)
      expect(response.dig("collection").first.dig("id")).to eq(other_quote.id)
      expect(response.dig("metadata", "totalCount")).to eq(1)
    end
  end

  context "when filtering by number" do
    let!(:other_quote) { create(:quote, organization:, customer:, sequential_id: 99999) }

    let(:query) do
      <<~GQL
        query {
          quotes(limit: 5, numbers: ["#{other_quote.number}"]) {
            collection { id number }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end

    it "returns the quote with the given number" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:
      )

      response = result.dig("data", "quotes")
      expect(response.dig("collection").count).to eq(1)
      expect(response.dig("collection").first.dig("id")).to eq(other_quote.id)
      expect(response.dig("collection").first.dig("number")).to eq(other_quote.number)
    end
  end

  context "when filtering by status" do
    let!(:approved_quote) { create(:quote, :with_version, version_trait: :approved, organization:, customer:) }

    let(:query) do
      <<~GQL
        query {
          quotes(limit: 5, statuses: [approved]) {
            collection { id }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end

    it "returns quotes with the specified version status" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:
      )

      response = result.dig("data", "quotes")
      expect(response.dig("collection").count).to eq(1)
      expect(response.dig("collection").first.dig("id")).to eq(approved_quote.id)
      expect(response.dig("metadata", "totalCount")).to eq(1)
    end
  end

  context "when filtering by from_date and to_date" do
    let!(:old_quote) { create(:quote, :with_version, organization:, customer:, created_at: 10.days.ago) }

    let(:query) do
      <<~GQL
        query {
          quotes(limit: 5, fromDate: "#{11.days.ago.to_date.iso8601}", toDate: "#{9.days.ago.to_date.iso8601}") {
            collection { id }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end

    it "returns quotes created within the provided date range" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:
      )

      response = result.dig("data", "quotes")
      expect(response.dig("collection").count).to eq(1)
      expect(response.dig("collection").first.dig("id")).to eq(old_quote.id)
      expect(response.dig("metadata", "totalCount")).to eq(1)
    end
  end

  context "when filtering by owners" do
    let(:owner_user) { membership.user }
    let(:query) do
      <<~GQL
        query {
          quotes(limit: 5, owners: ["#{owner_user.id}"]) {
            collection { id }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end
    let!(:owner_quote) { create(:quote, organization:, customer:) }

    before do
      QuoteOwner.create!(organization: organization, quote: owner_quote, user: owner_user)
    end

    it "returns quotes that belong to the specified owners" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:
      )

      expect(result["errors"]).to be_nil
      response = result.dig("data", "quotes")
      expect(response.dig("collection").count).to eq(1)
      expect(response.dig("collection").first.dig("id")).to eq(owner_quote.id)
      expect(response.dig("metadata", "totalCount")).to eq(1)
    end
  end
end
