# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Wallets::Alerts::Create do
  subject(:result) do
    execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input:
      }
    )
  end

  let(:required_permission) { "wallets:update" }
  let(:mutation) do
    <<-GQL
    mutation ($input: CreateCustomerWalletAlertInput!) {
      createCustomerWalletAlert(input: $input) {
        walletId
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
  let(:membership) { create(:membership) }
  let(:customer) { create(:customer, organization: membership.organization) }
  let(:wallet) { create(:wallet, customer:) }

  let(:input) do
    {
      walletId: wallet.id,
      code: "wallet_balance_alert",
      alertType: "wallet_balance_amount",
      thresholds: [
        {code: "warn", value: "5000"},
        {code: "alert", value: "2500"},
        {value: "1000", recurring: true}
      ]
    }
  end

  before do
    wallet
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "wallets:update"

  it "creates an alert" do
    result_data = result["data"]["createCustomerWalletAlert"]

    expect(result_data["subscriptionExternalId"]).to be_nil
    expect(result_data["walletId"]).to eq wallet.id
    expect(result_data["alertType"]).to eq "wallet_balance_amount"
    expect(result_data["code"]).to eq "wallet_balance_alert"
    expect(result_data["thresholds"]).to contain_exactly(
      {"code" => "warn", "value" => "5000.0", "recurring" => false}, # Notice .0 since it's a BigDecimal
      {"code" => "alert", "value" => "2500.0", "recurring" => false},
      {"code" => nil, "value" => "1000.0", "recurring" => true}
    )
  end

  context "with notifyOn" do
    let(:mutation) do
      <<-GQL
      mutation ($input: CreateCustomerWalletAlertInput!) {
        createCustomerWalletAlert(input: $input) {
          thresholds { code notifyOn }
        }
      }
      GQL
    end

    let(:input) do
      {
        walletId: wallet.id,
        code: "wallet_balance_alert",
        alertType: "wallet_balance_amount",
        thresholds: [
          {code: "warn", value: "5000", notifyOn: %w[triggered resolved]},
          {code: "alert", value: "2500"}
        ]
      }
    end

    it "round-trips the opted-in transitions" do
      expect(result["data"]["createCustomerWalletAlert"]["thresholds"]).to contain_exactly(
        {"code" => "warn", "notifyOn" => %w[triggered resolved]},
        {"code" => "alert", "notifyOn" => %w[triggered]}
      )
    end

    context "when a threshold opts in without a code" do
      let(:input) do
        {
          walletId: wallet.id,
          code: "wallet_balance_alert",
          alertType: "wallet_balance_amount",
          thresholds: [{value: "5000", notifyOn: %w[triggered resolved]}]
        }
      end

      it "returns a validation error" do
        expect(result["errors"].first["extensions"]["details"]).to eq({"thresholds:code" => ["value_is_mandatory"]})
      end
    end
  end
end
