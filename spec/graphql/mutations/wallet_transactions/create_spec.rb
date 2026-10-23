# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::WalletTransactions::Create do
  subject(:result) { execute_query(query:, input:) }

  let(:required_permission) { %w[wallets:top_up wallets:update] }
  let(:subscription) { create(:subscription, customer:) }
  let(:wallet) { create(:wallet, customer:, balance: 10.0, credits_balance: 10.0) }
  let(:query) do
    <<-GQL
    mutation ($input: CreateCustomerWalletTransactionInput!) {
      createCustomerWalletTransaction(input: $input) {
        collection {
          id
          status
          priority
          source
          name
          purchaseOrderNumber
          invoiceRequiresSuccessfulPayment
          transactionStatus
          transactionType
          creditAmount
          amount
          metadata {
            key
            value
          }
        }
      }
    }
    GQL
  end
  let(:input) do
    {
      walletId: wallet.id,
      name: "Test Transaction",
      paidCredits: "5.00",
      grantedCredits: "15.00",
      invoiceRequiresSuccessfulPayment: true,
      priority: 25,
      purchaseOrderNumber: "PO-123",
      metadata: [
        {
          key: "fixed",
          value: "0"
        },
        {
          key: "test 2",
          value: "mew meta"
        }
      ]
    }
  end

  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:plan) { create_default(:plan) }
  let_it_be(:membership) { create_default(:membership, organization:) }
  let_it_be(:customer) { create_default(:customer, organization:) }

  before do
    subscription
    wallet
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "wallets:top_up"

  it "creates a wallet transaction" do
    result_data = result["data"]["createCustomerWalletTransaction"]
    transactions = result_data["collection"].sort_by { |wt| wt["transactionStatus"] }

    expect(transactions.length).to eq(2)
    expect(transactions).to all(include(
      "metadata" => contain_exactly(
        {"key" => "fixed", "value" => "0"},
        {"key" => "test 2", "value" => "mew meta"}
      ),
      "name" => "Test Transaction",
      "priority" => 25,
      "transactionType" => "inbound",
      "source" => "manual"
    ))

    granted_transaction = transactions.first
    paid_transaction = transactions.second

    expect(granted_transaction).to include(
      "transactionStatus" => "granted",
      "status" => "settled",
      "creditAmount" => "15.0",
      "amount" => "15.0",
      "invoiceRequiresSuccessfulPayment" => false
    )

    expect(paid_transaction).to include(
      "transactionStatus" => "purchased",
      "status" => "pending",
      "creditAmount" => "5.0",
      "amount" => "5.0",
      "invoiceRequiresSuccessfulPayment" => true
    )
  end

  context "with wallets:top_up only" do
    let(:required_permission) { "wallets:top_up" }

    context "when granting credits" do
      let(:input) { {walletId: wallet.id, grantedCredits: "15.00"} }

      it "returns a forbidden error requiring wallets:update" do
        expect { result }.not_to change(organization.wallet_transactions, :count)
        expect_forbidden_error(result)
        expect(result["errors"].first["extensions"]["required_permissions"]).to eq(["wallets:update"])
      end
    end

    context "when voiding credits" do
      let(:input) { {walletId: wallet.id, voidedCredits: "5.00"} }

      it "returns a forbidden error" do
        expect { result }.not_to change(organization.wallet_transactions, :count)
        expect_forbidden_error(result)
        expect(wallet.reload.credits_balance).to eq(10)
      end
    end

    context "when topping up with the default top-up form values" do
      let(:input) do
        {
          walletId: wallet.id,
          paidCredits: "5.00",
          grantedCredits: "0",
          ignorePaidTopUpLimits: false
        }
      end

      it "creates the paid wallet transaction" do
        result_data = result["data"]["createCustomerWalletTransaction"]

        expect(result_data["collection"]).to contain_exactly(include(
          "transactionStatus" => "purchased",
          "creditAmount" => "5.0"
        ))
      end
    end
  end

  context "when wallet has a minimum amount" do
    before do
      wallet.update!(paid_top_up_min_amount_cents: 10_00)
    end

    it "returns an error" do
      # TODO: check error content when we return metadata
      expect_unprocessable_entity(result)
    end

    context "when the ignore_paid_top_up_limits is passed" do
      let(:input) do
        {
          walletId: wallet.id,
          paidCredits: "5.00",
          ignorePaidTopUpLimits: true
        }
      end

      it "creates the transaction" do
        expect { subject }.to change(organization.wallet_transactions, :count).by(1)

        result_data = result["data"]["createCustomerWalletTransaction"]
        expect(result_data["collection"].count).to eq 1
      end

      context "with wallets:top_up only" do
        let(:required_permission) { "wallets:top_up" }

        it "returns a forbidden error" do
          expect { subject }.not_to change(organization.wallet_transactions, :count)
          expect_forbidden_error(result)
        end
      end
    end
  end
end
