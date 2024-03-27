# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::PlansResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query {
        plans(limit: 5) {
          collection { id chargesCount customersCount }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:plan) { create(:plan, organization:) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }

  before do
    plan
    customer

    2.times do
      create(:subscription, customer:, plan:)
    end
  end

  it "returns a list of plans" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query:
    )

    plans_response = result["data"]["plans"]

    aggregate_failures do
      expect(plans_response["collection"].count).to eq(organization.plans.count)
      expect(plans_response["collection"].first["id"]).to eq(plan.id)
      expect(plans_response["collection"].first["customersCount"]).to eq(1)

      expect(plans_response["metadata"]["currentPage"]).to eq(1)
      expect(plans_response["metadata"]["totalCount"]).to eq(1)
    end
  end

  context "without current organization" do
    it "returns an error" do
      result = execute_graphql(current_user: membership.user, query:)

      expect_graphql_error(result:, message: "Missing organization id")
    end
  end

  context "when not member of the organization" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: create(:organization),
        query:
      )

      expect_graphql_error(result:, message: "Not in organization")
    end
  end
end
