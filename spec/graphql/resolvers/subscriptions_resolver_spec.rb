# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::SubscriptionsResolver do
  let(:required_permission) { "subscriptions:view" }
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

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "subscriptions:view"

  it "returns a list of subscriptions" do
    first_subscription = create(:subscription, customer:, plan:)
    second_subscription = create(:subscription, customer:, plan:)
    create(:subscription, customer:, plan:, status: :terminated)
    create(:subscription, customer:)

    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:
    )
    response = result["data"]["subscriptions"]

    aggregate_failures do
      expect(response["collection"].count).to eq(2)
      expect(response["collection"].map { |s| s["id"] }).to contain_exactly(
        first_subscription.id,
        second_subscription.id
      )
      expect(response["collection"].first["plan"]).to include(
        "code" => plan.code
      )

      expect(response["metadata"]["currentPage"]).to eq(1)
      expect(response["metadata"]["totalCount"]).to eq(2)
    end
  end
end
