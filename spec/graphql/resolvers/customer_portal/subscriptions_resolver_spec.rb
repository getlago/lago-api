# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::CustomerPortal::SubscriptionsResolver do
  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:user) { create_default(:user) }
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
  let(:organization) { membership.organization }
  let(:active_subscription) { create(:subscription, customer:, plan:) }
  let(:terminated_subscription) { create(:subscription, :terminated, customer:, plan:) }

  let_it_be(:membership) { create_default(:membership) }
  let_it_be(:customer) { create_default(:customer, organization:) }
  let_it_be(:plan) { create_default(:plan, organization:) }

  before do
    active_subscription
    terminated_subscription
  end

  it_behaves_like "requires a customer portal user"

  it "returns a list of subscriptions" do
    result = execute_graphql(customer_portal_user: customer, query:)

    subscriptions_response = result["data"]["customerPortalSubscriptions"]

    expect(subscriptions_response["collection"].pluck("id")).to contain_exactly(active_subscription.id)
    expect(subscriptions_response["metadata"]["currentPage"]).to eq(1)
    expect(subscriptions_response["metadata"]["totalCount"]).to eq(1)
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

      expect(subscriptions_response["collection"].first["id"]).to eq(terminated_subscription.id)
      expect(subscriptions_response["metadata"]["totalCount"]).to eq(1)
    end
  end

  context "with currency filter" do
    let(:brl_plan) { create(:plan, organization:, amount_currency: "BRL") }
    let!(:brl_subscription) { create(:subscription, customer:, plan: brl_plan) }

    let(:query) do
      <<~GQL
        query {
          customerPortalSubscriptions(currency: "#{brl_plan.amount_currency}", status: [active]) {
            collection { id }
            metadata { totalCount }
          }
        }
      GQL
    end

    it "returns only subscriptions with matching currency" do
      result = execute_graphql(customer_portal_user: customer, query:)
      response = result["data"]["customerPortalSubscriptions"]

      expect(response["collection"].count).to eq(1)
      expect(response["collection"].first["id"]).to eq(brl_subscription.id)
      expect(response["metadata"]["totalCount"]).to eq(1)
    end
  end

  context "without customer portal user" do
    it "returns an error" do
      result = execute_graphql(query:)
      expect_unauthorized_error(result)
    end
  end
end
