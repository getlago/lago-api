# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::Admin::OrganizationsResolver do
  let(:query) do
    <<~GQL
      query($searchTerm: String, $page: Int, $limit: Int) {
        adminOrganizations(searchTerm: $searchTerm, page: $page, limit: $limit) {
          collection { id name premiumIntegrations featureFlags }
          metadata { currentPage totalCount }
        }
      }
    GQL
  end

  let(:admin_user) { create(:user, email: "cs@getlago.com", cs_admin: true) }

  let!(:acme) { create(:organization, name: "ACME Corp", created_at: 2.days.ago) }
  let!(:hooli) { create(:organization, name: "Hooli", created_at: 1.day.ago) }

  def fetch(**variables)
    result = execute_graphql(current_user: admin_user, query:, variables:)
    result["data"]["adminOrganizations"]
  end

  it "returns every organization, newest first", :premium do
    organizations = fetch

    expect(organizations["metadata"]["totalCount"]).to eq(2)
    expect(organizations["collection"].map { |org| org["id"] }).to eq([hooli.id, acme.id])
  end

  it "filters by name with the search term", :premium do
    organizations = fetch(searchTerm: "acme")

    expect(organizations["collection"].map { |org| org["id"] }).to eq([acme.id])
  end

  it "filters by id with the search term", :premium do
    organizations = fetch(searchTerm: hooli.id)

    expect(organizations["collection"].map { |org| org["id"] }).to eq([hooli.id])
  end

  it "returns no organization when the search term matches nothing", :premium do
    organizations = fetch(searchTerm: "does-not-exist")

    expect(organizations["collection"]).to be_empty
  end

  it "paginates the results", :premium do
    organizations = fetch(page: 2, limit: 1)

    expect(organizations["metadata"]["currentPage"]).to eq(2)
    expect(organizations["metadata"]["totalCount"]).to eq(2)
    expect(organizations["collection"].map { |org| org["id"] }).to eq([acme.id])
  end

  it "exposes only the known feature flags", :premium do
    acme.update!(feature_flags: ["order_forms", "gone_flag"])

    organizations = fetch(searchTerm: "acme")

    expect(organizations["collection"].first["featureFlags"]).to eq(["order_forms"])
  end

  context "when the license is not premium" do
    it "returns an unauthorized error" do
      result = execute_graphql(current_user: admin_user, query:, variables: {})

      expect_graphql_error(result:, message: "unauthorized")
    end
  end

  context "when the user is not a CS admin" do
    let(:regular_user) { create(:user, email: "user@acme.test") }

    it "returns an unauthorized error" do
      result = execute_graphql(current_user: regular_user, query:, variables: {})

      expect_graphql_error(result:, message: "unauthorized")
    end
  end
end
