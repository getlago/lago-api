# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::Wallets::AlertResolver do
  let_it_be(:customer) { create_default(:customer) }
  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:user) { create_default(:user) }
  let(:required_permission) { "wallets:update" }
  let(:organization) { membership.organization }
  let(:alert) { create(:wallet_balance_amount_alert, organization:, recurring_threshold: 10, thresholds: [75, 50, 25]) }
  let(:query) do
    <<~GQL
      query($alertId: ID!) {
        walletAlert(id: $alertId) {
          id code name thresholds {code value recurring}
        }
      }
    GQL
  end

  let_it_be(:membership) { create_default(:membership) }

  before do
    alert
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "wallets:update"

  it "returns a single alert" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {alertId: alert.id}
    )

    alert_response = result["data"]["walletAlert"]

    expect(alert_response["id"]).to eq(alert.id)
    expect(alert_response["code"]).to start_with("default")
    expect(alert_response["name"]).to eq("General Alert")
    expect(alert_response["thresholds"].map(&:symbolize_keys)).to contain_exactly(
      {code: "warn75", value: "75.0", recurring: false},
      {code: "warn50", value: "50.0", recurring: false},
      {code: "warn25", value: "25.0", recurring: false},
      {code: "rec", value: "10.0", recurring: true}
    )
  end

  context "when alert is not found" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {alertId: "invalid"}
      )

      expect_graphql_error(result:, message: "Resource not found")
    end
  end
end
