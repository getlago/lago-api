# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Subscriptions::Create, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:plan) { create(:plan, organization:) }
  let(:charge) { create(:standard_charge, plan:) }
  let(:ending_at) { Time.current.beginning_of_day + 1.year }
  let(:customer) { create(:customer, organization:) }
  let(:mutation) do
    <<~GQL
      mutation($input: CreateSubscriptionInput!) {
        createSubscription(input: $input) {
          id
          status
          name
          externalId
          startedAt
          billingTime
          subscriptionAt
          endingAt
          customer {
            id
          },
          plan {
            id
            amountCents
          }
        }
      }
    GQL
  end

  around { |test| lago_premium!(&test) }

  it "creates a subscription", :aggregate_failures do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query: mutation,
      variables: {
        input: {
          customerId: customer.id,
          planId: plan.id,
          name: "name",
          externalId: "custom-external-id",
          billingTime: "anniversary",
          endingAt: ending_at.iso8601,
          planOverrides: {
            amountCents: 100,
            charges: [
              id: charge.id,
              billableMetricId: charge.billable_metric_id,
              invoiceDisplayName: "invoice display name"
            ]
          }
        }
      }
    )

    result_data = result["data"]["createSubscription"]

    expect(result_data).to include(
      "id" => String,
      "status" => "active",
      "name" => "name",
      "externalId" => "custom-external-id",
      "startedAt" => String,
      "billingTime" => "anniversary",
      "endingAt" => ending_at.iso8601
    )
    expect(result_data["customer"]).to include(
      "id" => customer.id
    )
    expect(result_data["plan"]).to include(
      "id" => String,
      "amountCents" => "100"
    )
  end

  context "without current user" do
    it "returns an error" do
      result = execute_graphql(
        current_organization: membership.organization,
        query: mutation,
        variables: {
          input: {
            customerId: customer.id,
            planId: plan.id,
            billingTime: "anniversary"
          }
        }
      )

      expect_unauthorized_error(result)
    end
  end

  context "without current organization" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        query: mutation,
        variables: {
          input: {
            customerId: customer.id,
            planId: plan.id,
            billingTime: "anniversary"
          }
        }
      )

      expect_forbidden_error(result)
    end
  end
end
