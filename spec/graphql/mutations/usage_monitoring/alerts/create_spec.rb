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
      createSubscriptionAlert(input: $input) {
        subscriptionExternalId
        alertType
        code
        thresholds {
          code
          value
          recurring
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

  it "creates an alert" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          subscriptionId: subscription.id,
          code: "global",
          alertType: "usage_amount",
          thresholds: [
            {code: "warn", value: "10"},
            {code: "alert", value: "50"},
            {value: "20", recurring: true}
          ]
        }
      }
    )

    result_data = result["data"]["createSubscriptionAlert"]
    expect(result_data["subscriptionExternalId"]).to eq subscription.external_id
    expect(result_data["alertType"]).to eq "usage_amount"
    expect(result_data["code"]).to eq "global"
    expect(result_data["thresholds"]).to contain_exactly(
      {"code" => "warn", "value" => "10.0", "recurring" => false}, # Notice .0 since it's a BigDecimal
      {"code" => "alert", "value" => "50.0", "recurring" => false},
      {"code" => nil, "value" => "20.0", "recurring" => true}
    )
  end
end
