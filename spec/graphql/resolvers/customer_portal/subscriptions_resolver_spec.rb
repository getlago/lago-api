# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::CustomerPortal::SubscriptionsResolver do
  let(:query) do
    <<~GQL
      query {
        customerPortalSubscriptions(limit: 5, planCode: "#{plan.code}", status: [active]) {
            collection { id externalId currentBillingPeriodStartedAt currentBillingPeriodEndingAt plan { code } }
            metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:active_subscription) { create(:subscription, customer:, plan:) }
  let(:terminated_subscription) { create(:subscription, :terminated, customer:, plan:) }

  before do
    active_subscription
    terminated_subscription
  end

  it_behaves_like "requires a customer portal user"

  it "returns a list of subscriptions" do
    result = execute_graphql(customer_portal_user: customer, query:)

    subscriptions_response = result["data"]["customerPortalSubscriptions"]

    aggregate_failures do
      expect(subscriptions_response["collection"].pluck("id")).to contain_exactly(active_subscription.id)
      expect(subscriptions_response["metadata"]["currentPage"]).to eq(1)
      expect(subscriptions_response["metadata"]["totalCount"]).to eq(1)
    end
  end

  context "with filter on status" do
    let(:query) do
      <<~GQL
        query($status: [StatusTypeEnum!]) {
          customerPortalSubscriptions(status: $status) {
            collection { id }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end

    it "only returns draft invoice" do
      result = execute_graphql(
        customer_portal_user: customer,
        query:,
        variables: {status: ["terminated"]}
      )

      subscriptions_response = result["data"]["customerPortalSubscriptions"]

      aggregate_failures do
        expect(subscriptions_response["collection"].first["id"]).to eq(terminated_subscription.id)
        expect(subscriptions_response["metadata"]["totalCount"]).to eq(1)
      end
    end
  end

  context "without customer portal user" do
    it "returns an error" do
      result = execute_graphql(query:)
      expect_unauthorized_error(result)
    end
  end
end
