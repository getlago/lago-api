# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::SubscriptionsResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query {
        subscriptions(limit: 5, planCode: "#{plan.code}", status: [active]) {
          collection { id externalId plan { code } }
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
    customer
  end

  it "returns a list of subscriptions" do
    first_subcription = create(:subscription, customer:, plan:)
    second_subcription = create(:subscription, customer:, plan:)
    create(:subscription, customer:, plan:, status: :terminated)
    create(:subscription, customer:)

    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query:
    )
    response = result["data"]["subscriptions"]

    aggregate_failures do
      expect(response["collection"].count).to eq(2)
      expect(response["collection"].map { |s| s["id"] }).to contain_exactly(
        first_subcription.id,
        second_subcription.id
      )
      expect(response["collection"].first["plan"]).to include(
        "code" => plan.code
      )

      expect(response["metadata"]["currentPage"]).to eq(1)
      expect(response["metadata"]["totalCount"]).to eq(2)
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
