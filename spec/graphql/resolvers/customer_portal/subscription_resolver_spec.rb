# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::CustomerPortal::SubscriptionResolver do
  let(:query) do
    <<~GQL
      query($subscriptionId: ID!) {
        customerPortalSubscription(id: $subscriptionId) {
          id
          name
          startedAt
          endingAt
          plan {
            id
            code
          }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:) }

  before do
    customer
  end

  it_behaves_like "requires a customer portal user"

  it "returns a single subscription" do
    result = execute_graphql(
      customer_portal_user: customer,
      query:,
      variables: {subscriptionId: subscription.id}
    )

    subscription_response = result["data"]["customerPortalSubscription"]
    expect(subscription_response).to include(
      "id" => subscription.id,
      "name" => subscription.name,
      "startedAt" => subscription.started_at.iso8601,
      "endingAt" => subscription.ending_at
    )

    expect(subscription_response["plan"]).to include(
      "id" => subscription.plan.id,
      "code" => subscription.plan.code
    )
  end

  context "when the plan has taxes" do
    let(:query) do
      <<~GQL
        query($subscriptionId: ID!) {
          customerPortalSubscription(id: $subscriptionId) {
            id
            plan {
              taxes { id appliedToOrganization appliedToBillingEntitiesCodes }
            }
          }
        }
      GQL
    end

    let(:plan) { create(:plan, organization:) }
    let(:subscription) { create(:subscription, customer:, plan:) }
    let(:tax) { create(:tax, :applied_to_billing_entity, organization:) }

    before { create(:plan_applied_tax, plan:, tax:, organization:) }

    it "derives applied_to_organization from the tax organization, not the request context" do
      result = execute_graphql(
        customer_portal_user: customer,
        query:,
        variables: {subscriptionId: subscription.id}
      )

      tax_response = result["data"]["customerPortalSubscription"]["plan"]["taxes"].first

      expect(tax_response["appliedToOrganization"]).to eq(true)
      expect(tax_response["appliedToBillingEntitiesCodes"]).to eq([organization.default_billing_entity.code])
    end
  end

  context "with several taxes on the plan" do
    let(:query) do
      <<~GQL
        query($subscriptionId: ID!) {
          customerPortalSubscription(id: $subscriptionId) {
            plan { taxes { appliedToBillingEntitiesCodes } }
          }
        }
      GQL
    end

    let(:plan) { create(:plan, organization:) }
    let(:subscription) { create(:subscription, customer:, plan:) }

    before do
      3.times do
        create(:plan_applied_tax, plan:, tax: create(:tax, :applied_to_billing_entity, organization:), organization:)
      end
    end

    it "batches the billing_entities loads across taxes (no N+1)" do
      count = 0
      counter = lambda do |_name, _start, _finish, _id, payload|
        count += 1 if payload[:sql]&.include?('FROM "billing_entities"')
      end

      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        execute_graphql(
          customer_portal_user: customer,
          query:,
          variables: {subscriptionId: subscription.id}
        )
      end

      expect(count).to be <= 1
    end
  end

  context "when subscription is not found" do
    it "returns an error" do
      result = execute_graphql(
        customer_portal_user: customer,
        query:,
        variables: {subscriptionId: "foo"}
      )

      expect_graphql_error(result:, message: "Resource not found")
    end
  end
end
