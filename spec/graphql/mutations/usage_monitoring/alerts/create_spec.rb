# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::UsageMonitoring::Alerts::Create, type: :graphql do
  let(:required_permission) { "subscriptions:update" }
  let(:membership) { create(:membership) }
  let(:customer) { create(:customer, organization: membership.organization) }
  let(:subscription) { create(:subscription, customer:) }

  let(:mutation) do
    <<-GQL
    mutation ($input: CreateSubscriptionAlertInput!) {
      CreateSubscriptionAlert(input: $input) {
        subscriptionId
        alertType
        code
        thresholds {
          code
          value
        }
      }
    }
    GQL
  end

  before do
    subscription
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "subscriptions:update"

  it "creates a wallet transaction" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          subscriptionId: subscription.id,
          code: "gloabal",
          alertType: "usage_amount",
          thresholds: [
            {
              code: "warn",
              value: "10"
            },
            {
              code: "alert",
              value: "50"
            }
          ]
        }
      }
    )

    pp result
    result_data = result["data"]["createCustomerWalletTransaction"]
    expect(result_data["collection"].map { |wt| wt["status"] })
      .to contain_exactly("pending", "settled")
    expect(result_data["collection"].map { |wt| wt["invoiceRequiresSuccessfulPayment"] }).to all be true
    expect(result_data["collection"]).to all(include(
      "metadata" => contain_exactly(
        {"key" => "fixed", "value" => "0"},
        {"key" => "test 2", "value" => "mew meta"}
      )
    ))
  end
end
