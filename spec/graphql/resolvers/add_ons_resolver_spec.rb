# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::AddOnsResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query {
        addOns(limit: 5) {
          collection { id name }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:add_on) { create(:add_on, organization:) }

  before { add_on }

  it "returns a list of add-ons" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query:
    )

    add_ons_response = result["data"]["addOns"]

    aggregate_failures do
      expect(add_ons_response["collection"].first["id"]).to eq(add_on.id)
      expect(add_ons_response["collection"].first["name"]).to eq(add_on.name)

      expect(add_ons_response["metadata"]["currentPage"]).to eq(1)
      expect(add_ons_response["metadata"]["totalCount"]).to eq(1)
    end
  end

  context "without current organization" do
    it "returns an error" do
      result = execute_graphql(current_user: membership.user, query:)

      expect_graphql_error(
        result:,
        message: "Missing organization id"
      )
    end
  end

  context "when not member of the organization" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: create(:organization),
        query:
      )

      expect_graphql_error(
        result:,
        message: "Not in organization"
      )
    end
  end
end
