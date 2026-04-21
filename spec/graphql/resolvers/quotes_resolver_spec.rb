# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::QuotesResolver do
  let(:required_permission) { "quotes:view" }
  let(:number) { "QT-2025-0001" }
  let(:latest_version_only) { true }
  let(:query) do
    <<~GQL
      query {
        quotes(limit: 5, number: "#{number}", latestVersionOnly: #{latest_version_only}) {
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
        number:,
        status: :voided,
        void_reason: :manual,
        voided_at: Time.current,
        version:
      )
    end
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "quotes:view"

  context "when all versions are requested" do
    let(:latest_version_only) { false }

    it "returns a full list of quotes" do
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
      expect(first_quote["number"]).to eq(number)
      expect(first_quote["version"]).to eq(5)

      last_quote = quotes_response["collection"].last
      expect(last_quote["number"]).to eq(number)
      expect(last_quote["version"]).to eq(1)
    end
  end

  context "when only latest version is requested" do
    let(:latest_version_only) { true }

    it "returns only the latest version of quotes" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:
      )

      quotes_response = result["data"]["quotes"]
      expect(quotes_response["collection"].count).to eq(1)
      expect(quotes_response["metadata"]["currentPage"]).to eq(1)
      expect(quotes_response["metadata"]["totalCount"]).to eq(1)

      quote = quotes_response["collection"].first
      expect(quote["number"]).to eq(number)
      expect(quote["version"]).to eq(5)
    end
  end
end
