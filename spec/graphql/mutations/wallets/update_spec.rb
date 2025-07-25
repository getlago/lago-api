# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Wallets::Update, type: :graphql do
  let(:required_permission) { "wallets:update" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:billable_metric) { create(:billable_metric, organization: membership.organization) }
  let(:subscription) { create(:subscription, customer:) }
  let(:wallet) { create(:wallet, customer:) }
  let(:expiration_at) { (Time.zone.now + 1.year) }
  let(:recurring_transaction_rule) { create(:recurring_transaction_rule, wallet:) }

  let(:mutation) do
    <<-GQL
      mutation($input: UpdateCustomerWalletInput!) {
        updateCustomerWallet(input: $input) {
          id
          name
          status
          expirationAt
          invoiceRequiresSuccessfulPayment
          recurringTransactionRules {
            lagoId
            method
            trigger
            interval
            thresholdCredits
            paidCredits
            grantedCredits
            targetOngoingBalance
            invoiceRequiresSuccessfulPayment
            expirationAt
            transactionMetadata {
              key
              value
            }
          }
          appliesTo {
            feeTypes
            billableMetrics {
              id
            }
          }
        }
      }
    GQL
  end

  before do
    subscription
    recurring_transaction_rule
  end

  around { |test| lago_premium!(&test) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "wallets:update"

  it "updates a wallet" do
    result = execute_graphql(
      current_organization: organization,
      current_user: membership.user,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          id: wallet.id,
          name: "New name",
          expirationAt: expiration_at.iso8601,
          invoiceRequiresSuccessfulPayment: true,
          recurringTransactionRules: [
            {
              lagoId: recurring_transaction_rule.id,
              method: "target",
              trigger: "interval",
              interval: "weekly",
              paidCredits: "22.2",
              grantedCredits: "22.2",
              targetOngoingBalance: "300",
              invoiceRequiresSuccessfulPayment: true,
              expirationAt: expiration_at.iso8601,
              transactionMetadata: [
                {key: "example_key", value: "example_value"},
                {key: "another_key", value: "another_value"}
              ]
            }
          ],
          appliesTo: {
            feeTypes: %w[subscription],
            billableMetricIds: [billable_metric.id]
          }
        }
      }
    )

    result_data = result["data"]["updateCustomerWallet"]

    expect(result_data).to include(
      "id" => wallet.id,
      "name" => "New name",
      "status" => "active",
      "invoiceRequiresSuccessfulPayment" => true,
      "expirationAt" => expiration_at.iso8601
    )

    expect(result_data["recurringTransactionRules"].count).to eq(1)
    expect(result_data["recurringTransactionRules"][0]["transactionMetadata"]).to contain_exactly(
      {"key" => "example_key", "value" => "example_value"},
      {"key" => "another_key", "value" => "another_value"}
    )
    expect(result_data["recurringTransactionRules"][0]).to include(
      "lagoId" => recurring_transaction_rule.id,
      "method" => "target",
      "trigger" => "interval",
      "interval" => "weekly",
      "paidCredits" => "22.2",
      "grantedCredits" => "22.2",
      "targetOngoingBalance" => "300.0",
      "invoiceRequiresSuccessfulPayment" => true
    )
    expect(result_data["appliesTo"]["feeTypes"]).to eq(["subscription"])
    expect(result_data["appliesTo"]["billableMetrics"].first["id"]).to eq(billable_metric.id)

    expect(SendWebhookJob).to have_been_enqueued.with("wallet.updated", Wallet)
  end
end
