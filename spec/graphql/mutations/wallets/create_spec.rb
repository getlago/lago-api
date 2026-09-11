# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Wallets::Create, :premium do
  let(:required_permission) { "wallets:create" }
  let(:membership) { create(:membership) }
  let(:customer) { create(:customer, organization: membership.organization, currency: "EUR") }
  let(:billable_metric) { create(:billable_metric, organization: membership.organization) }
  let(:expiration_at) { Time.zone.now + 1.year }

  let(:mutation) do
    <<-GQL
      mutation($input: CreateCustomerWalletInput!) {
        createCustomerWallet(input: $input) {
          id
          code
          name
          priority
          purchaseOrderNumber
          rateAmount
          status
          currency
          expirationAt
          invoiceRequiresSuccessfulPayment
          paidTopUpMinAmountCents
          paidTopUpMaxAmountCents
          metadata {
            key
            value
          }
          recurringTransactionRules {
            lagoId
            method
            trigger
            interval
            thresholdCredits
            paidCredits
            grantedCredits
            grantsTargetTopUp
            targetOngoingBalance
            invoiceRequiresSuccessfulPayment
            expirationAt
            ignorePaidTopUpLimits
            transactionMetadata {
              key
              value
            }
            transactionName
            purchaseOrderNumber
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

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "wallets:create"

  it "creates a wallet" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          customerId: customer.id,
          name: "First Wallet",
          priority: 9,
          purchaseOrderNumber: "PO-123",
          rateAmount: "1",
          paidCredits: "10.00",
          grantedCredits: "0.00",
          expirationAt: expiration_at.iso8601,
          currency: "EUR",
          invoiceRequiresSuccessfulPayment: true,
          paidTopUpMinAmountCents: 1_00,
          paidTopUpMaxAmountCents: 100_00,
          transactionName: "Initial Credits Purchase",
          recurringTransactionRules: [
            {
              method: "target",
              trigger: "interval",
              interval: "monthly",
              targetOngoingBalance: "0.0",
              invoiceRequiresSuccessfulPayment: true,
              expirationAt: expiration_at.iso8601,
              ignorePaidTopUpLimits: true,
              grantsTargetTopUp: true,
              transactionMetadata: [
                {key: "example_key", value: "example_value"},
                {key: "another_key", value: "another_value"}
              ],
              transactionName: "Monthly AI Credits Top-up",
              purchaseOrderNumber: "PO-456"
            }
          ],
          appliesTo: {
            feeTypes: %w[subscription],
            billableMetricIds: [billable_metric.id]
          }
        }
      }
    )

    result_data = result["data"]["createCustomerWallet"]

    expect(result_data["id"]).to be_present
    expect(result_data["code"]).to eq("first_wallet")
    expect(result_data["name"]).to eq("First Wallet")
    expect(result_data["priority"]).to eq(9)
    expect(result_data["purchaseOrderNumber"]).to eq("PO-123")
    expect(result_data["invoiceRequiresSuccessfulPayment"]).to eq(true)
    expect(result_data["expirationAt"]).to eq(expiration_at.iso8601)
    expect(result_data["paidTopUpMinAmountCents"]).to eq("100")
    expect(result_data["paidTopUpMaxAmountCents"]).to eq("10000")
    expect(result_data["recurringTransactionRules"].count).to eq(1)
    expect(result_data["recurringTransactionRules"][0]["lagoId"]).to be_present
    expect(result_data["recurringTransactionRules"][0]["method"]).to eq("target")
    expect(result_data["recurringTransactionRules"][0]["trigger"]).to eq("interval")
    expect(result_data["recurringTransactionRules"][0]["interval"]).to eq("monthly")
    expect(result_data["recurringTransactionRules"][0]["paidCredits"]).to eq("0.0")
    expect(result_data["recurringTransactionRules"][0]["grantedCredits"]).to eq("0.0")
    expect(result_data["recurringTransactionRules"][0]["invoiceRequiresSuccessfulPayment"]).to eq(true)
    expect(result_data["recurringTransactionRules"][0]["ignorePaidTopUpLimits"]).to eq(true)
    expect(result_data["recurringTransactionRules"][0]["grantsTargetTopUp"]).to eq(true)
    expect(result_data["recurringTransactionRules"][0]["transactionMetadata"]).to contain_exactly(
      {"key" => "example_key", "value" => "example_value"},
      {"key" => "another_key", "value" => "another_value"}
    )
    expect(result_data["recurringTransactionRules"][0]["transactionName"]).to eq("Monthly AI Credits Top-up")
    expect(result_data["recurringTransactionRules"][0]["purchaseOrderNumber"]).to eq("PO-456")
    expect(result_data["appliesTo"]["feeTypes"]).to eq(["subscription"])
    expect(result_data["appliesTo"]["billableMetrics"].first["id"]).to eq(billable_metric.id)

    expect(WalletTransactions::CreateJob).to have_been_enqueued.with(
      organization_id: membership.organization.id,
      params: {
        wallet_id: Regex::UUID,
        paid_credits: "10.00",
        granted_credits: "0.00",
        source: :manual,
        metadata: nil,
        priority: nil,
        name: "Initial Credits Purchase",
        ignore_paid_top_up_limits: nil,
        purchase_order_number: "PO-456"
      }
    )
    expect(SendWebhookJob).to have_been_enqueued.with("wallet.created", Wallet)
  end

  context "when wallet purchase order number is present and recurring rule purchase order number is nil" do
    it "enqueues the initial top-up with the wallet purchase order number" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {
            customerId: customer.id,
            name: "Wallet PO Fallback",
            priority: 9,
            purchaseOrderNumber: "PO-WALLET-123",
            rateAmount: "1",
            paidCredits: "10.00",
            grantedCredits: "0.00",
            expirationAt: expiration_at.iso8601,
            currency: "EUR",
            recurringTransactionRules: [
              {
                method: "target",
                trigger: "interval",
                interval: "monthly",
                targetOngoingBalance: "0.0",
                purchaseOrderNumber: nil
              }
            ]
          }
        }
      )

      result_data = result["data"]["createCustomerWallet"]
      expect(result_data["purchaseOrderNumber"]).to eq("PO-WALLET-123")
      expect(result_data["recurringTransactionRules"][0]["purchaseOrderNumber"]).to be_nil

      expect(WalletTransactions::CreateJob).to have_been_enqueued.with(
        organization_id: membership.organization.id,
        params: hash_including(purchase_order_number: "PO-WALLET-123")
      )
    end
  end

  context "when wallet purchase order number is nil and recurring rule purchase order number is present" do
    it "enqueues the initial top-up with the recurring rule purchase order number" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {
            customerId: customer.id,
            name: "Rule PO Fallback",
            priority: 9,
            purchaseOrderNumber: nil,
            rateAmount: "1",
            paidCredits: "10.00",
            grantedCredits: "0.00",
            expirationAt: expiration_at.iso8601,
            currency: "EUR",
            recurringTransactionRules: [
              {
                method: "target",
                trigger: "interval",
                interval: "monthly",
                targetOngoingBalance: "0.0",
                purchaseOrderNumber: "PO-RULE-456"
              }
            ]
          }
        }
      )

      result_data = result["data"]["createCustomerWallet"]
      expect(result_data["purchaseOrderNumber"]).to be_nil
      expect(result_data["recurringTransactionRules"][0]["purchaseOrderNumber"]).to eq("PO-RULE-456")

      expect(WalletTransactions::CreateJob).to have_been_enqueued.with(
        organization_id: membership.organization.id,
        params: hash_including(purchase_order_number: "PO-RULE-456")
      )
    end
  end

  context "when grants_target_top_up is omitted on a target rule" do
    it "defaults grants_target_top_up to false" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {
            customerId: customer.id,
            name: "Default Wallet",
            priority: 9,
            rateAmount: "1",
            paidCredits: "0.00",
            grantedCredits: "0.00",
            expirationAt: expiration_at.iso8601,
            currency: "EUR",
            recurringTransactionRules: [
              {
                method: "target",
                trigger: "interval",
                interval: "monthly",
                targetOngoingBalance: "0.0"
              }
            ]
          }
        }
      )

      result_data = result["data"]["createCustomerWallet"]

      expect(result_data["recurringTransactionRules"].count).to eq(1)
      expect(result_data["recurringTransactionRules"][0]).to include("grantsTargetTopUp" => false)
    end
  end

  context "when name is not present" do
    it "creates a wallet with default code" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {
            customerId: customer.id,
            name: nil,
            priority: 11,
            rateAmount: "1",
            paidCredits: "0.00",
            grantedCredits: "0.00",
            expirationAt: (Time.zone.now + 1.year).iso8601,
            currency: "EUR"
          }
        }
      )

      result_data = result["data"]["createCustomerWallet"]

      expect(result_data["id"]).to be_present
      expect(result_data["name"]).to be_nil
      expect(result_data["code"]).to eq("default")
    end
  end

  context "when code is provided" do
    it "creates a wallet with the provided code" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {
            customerId: customer.id,
            name: "My Wallet",
            code: "custom_code",
            priority: 9,
            rateAmount: "1",
            paidCredits: "0.00",
            grantedCredits: "0.00",
            expirationAt: expiration_at.iso8601,
            currency: "EUR"
          }
        }
      )

      result_data = result["data"]["createCustomerWallet"]

      expect(result_data["id"]).to be_present
      expect(result_data["code"]).to eq("custom_code")
      expect(result_data["name"]).to eq("My Wallet")
    end
  end

  context "when code is already taken for the customer" do
    before do
      create(:wallet, customer:, code: "existing_code")
    end

    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {
            customerId: customer.id,
            name: "My Wallet",
            code: "existing_code",
            priority: 9,
            rateAmount: "1",
            paidCredits: "0.00",
            grantedCredits: "0.00",
            expirationAt: expiration_at.iso8601,
            currency: "EUR"
          }
        }
      )

      expect_unprocessable_entity(result, details: {code: ["value_already_exist"]})
    end
  end

  context "when transaction_name is not provided" do
    it "creates a wallet with null transaction_name" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {
            customerId: customer.id,
            name: "Test Wallet",
            priority: 9,
            rateAmount: "1",
            paidCredits: "10.00",
            grantedCredits: "0.00",
            expirationAt: expiration_at.iso8601,
            currency: "EUR",
            recurringTransactionRules: [
              {
                method: "fixed",
                trigger: "interval",
                interval: "monthly",
                paidCredits: "10.0",
                grantedCredits: "5.0"
              }
            ]
          }
        }
      )

      result_data = result["data"]["createCustomerWallet"]

      expect(result_data["id"]).to be_present
      expect(result_data["recurringTransactionRules"].count).to eq(1)
      expect(result_data["recurringTransactionRules"][0]["transactionName"]).to be_nil

      expect(WalletTransactions::CreateJob).to have_been_enqueued.with(
        organization_id: membership.organization.id,
        params: {
          wallet_id: Regex::UUID,
          paid_credits: "10.00",
          granted_credits: "0.00",
          source: :manual,
          metadata: nil,
          priority: nil,
          name: nil,
          ignore_paid_top_up_limits: nil,
          purchase_order_number: nil
        }
      )
    end
  end

  context "with metadata" do
    it "creates a wallet with metadata" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {
            customerId: customer.id,
            name: "Wallet with Metadata",
            priority: 9,
            rateAmount: "1",
            paidCredits: "0.00",
            grantedCredits: "0.00",
            expirationAt: expiration_at.iso8601,
            currency: "EUR",
            metadata: [
              {key: "env", value: "production"},
              {key: "team", value: "engineering"}
            ]
          }
        }
      )

      result_data = result["data"]["createCustomerWallet"]

      expect(result_data["id"]).to be_present
      expect(result_data["name"]).to eq("Wallet with Metadata")
      expect(result_data["metadata"]).to contain_exactly(
        {"key" => "env", "value" => "production"},
        {"key" => "team", "value" => "engineering"}
      )
    end
  end

  context "with connections" do
    let(:organization) { membership.organization }
    let(:stripe_connection) { create(:stripe_customer, customer:, code: "stripe_us") }
    let(:netsuite_connection) { create(:netsuite_customer, customer:, code: "netsuite_main") }

    let(:connections_mutation) do
      <<-GQL
        mutation($input: CreateCustomerWalletInput!) {
          createCustomerWallet(input: $input) {
            id
            recurringTransactionRules { lagoId }
          }
        }
      GQL
    end

    def create_wallet(connections:, rule_connections: nil)
      rules = if rule_connections
        [{trigger: "interval", interval: "monthly", method: "fixed", connections: rule_connections}]
      end

      input = {
        customerId: customer.id,
        name: "Connected Wallet",
        priority: 1,
        rateAmount: "1",
        paidCredits: "10.00",
        grantedCredits: "0.00",
        currency: "EUR",
        connections:
      }
      input[:recurringTransactionRules] = rules if rules

      execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: connections_mutation,
        variables: {input:}
      )
    end

    before do
      organization.enable_feature_flag!(:multi_connection)
      stripe_connection
      netsuite_connection
    end

    it "persists one connection per category" do
      result = create_wallet(
        connections: {
          payment: {code: "stripe_us"},
          tax: {behavior: "skip"},
          accounting: {code: "netsuite_main"},
          crm: {behavior: "skip"}
        }
      )

      wallet = Wallet.find(result["data"]["createCustomerWallet"]["id"])
      expect(wallet.billing_object_connections.pluck(:category)).to match_array(%w[payment tax accounting crm])
      expect(wallet.effective_payment_connection).to eq(stripe_connection)
      expect(wallet.effective_accounting_connection).to eq(netsuite_connection)
      expect(wallet.effective_tax_connection).to be_nil
    end

    it "pins a per-rule connection on the rule rather than the wallet" do
      result = create_wallet(
        connections: {tax: {behavior: "skip"}},
        rule_connections: {payment: {code: "stripe_us"}}
      )

      wallet = Wallet.find(result["data"]["createCustomerWallet"]["id"])
      rule = wallet.recurring_transaction_rules.sole

      expect(wallet.billing_object_connections.pluck(:category)).to eq(%w[tax])
      expect(rule.billing_object_connections.sole).to have_attributes(
        category: "payment",
        behavior: "specific",
        payment_provider_customer_id: stripe_connection.id
      )
    end

    it "returns a validation error when the code does not resolve" do
      result = create_wallet(connections: {payment: {code: "unknown_connection"}})

      expect(result["errors"].first["extensions"]["details"]["connections"]).to include("connection_not_found")
    end

    it "returns a forbidden error when the multi_connection flag is disabled" do
      organization.disable_feature_flag!(:multi_connection)

      result = create_wallet(connections: {payment: {code: "stripe_us"}})

      expect(result["errors"].first["extensions"]["code"]).to eq("feature_unavailable")
    end
  end
end
