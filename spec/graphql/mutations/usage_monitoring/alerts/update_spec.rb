# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::UsageMonitoring::Alerts::Update, type: :graphql do
  let(:required_permission) { "subscriptions:update" }
  let(:membership) { create(:membership) }
  let(:customer) { create(:customer, organization: membership.organization) }
  let(:subscription) { create(:subscription, customer:, organization: membership.organization) }
  let(:alert) { create(:usage_amount_alert, subscription_external_id: subscription.external_id, organization: membership.organization, recurring_threshold: 33, thresholds: [10, 20, 22]) }

  let(:mutation) do
    <<-GQL
    mutation ($input: UpdateSubscriptionAlertInput!) {
      updateSubscriptionAlert(input: $input) {
        id
        alertType
        code
        recurringThreshold
        thresholds {
          code
          value
        }
        billableMetric { id code }
      }
    }
    GQL
  end

  before do
    subscription
    alert
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "subscriptions:update"

  it "updates an alert" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          id: alert.id,
          code: "new code",
          recurringThreshold: "60",
          thresholds: [
            {code: "warn", value: "10"},
            {code: "alert", value: "50"}
          ]
        }
      }
    )

    result_data = result["data"]["updateSubscriptionAlert"]
    expect(result_data["id"]).to eq alert.id
    expect(result_data["alertType"]).to eq "usage_amount"
    expect(result_data["code"]).to eq "new code"
    expect(result_data["billableMetric"]).to be_nil
    expect(result_data["recurringThreshold"]).to eq "60.0"
    expect(result_data["thresholds"]).to contain_exactly(
      {"code" => "warn", "value" => "10.0"},
      {"code" => "alert", "value" => "50.0"}
    )
  end

  context "with new billable_metric" do
    let(:alert) { create(:billable_metric_usage_amount_alert, subscription_external_id: subscription.external_id, organization: membership.organization, recurring_threshold: 33, thresholds: [10, 12]) }

    it "updates the alert" do
      new_billable_metric = create(:billable_metric, code: "new_bm", organization: membership.organization)

      result = execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {
            id: alert.id,
            code: "new code",
            recurringThreshold: "60",
            billableMetricId: new_billable_metric.id
          }
        }
      )

      result_data = result["data"]["updateSubscriptionAlert"]
      expect(result_data["id"]).to eq alert.id
      expect(result_data["alertType"]).to eq "billable_metric_usage_amount"
      expect(result_data["code"]).to eq "new code"
      expect(result_data["recurringThreshold"]).to eq "60.0"
      expect(result_data["thresholds"]).to contain_exactly(
        {"code" => "warn10", "value" => "10.0"},
        {"code" => "warn12", "value" => "12.0"}
      )
      expect(result_data["billableMetric"]["id"]).to eq new_billable_metric.id
      expect(result_data["billableMetric"]["code"]).to eq "new_bm"
    end
  end
end
