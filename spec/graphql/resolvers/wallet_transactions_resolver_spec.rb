# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::WalletTransactionsResolver do
  let_it_be(:plan) { create_default(:plan) }
  let_it_be(:organization, refind: true) { create_default(:organization) }
  let_it_be(:user) { create_default(:user) }
  let(:query) do
    <<~GQL
      query($walletId: ID!) {
        walletTransactions(walletId: $walletId, limit: 5, status: settled) {
          collection { id }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end
  let(:subscription) { create(:subscription, customer:, organization:) }
  let(:wallet) { create(:wallet, customer:) }
  let(:wallet_transaction) { create(:wallet_transaction, wallet:) }

  let_it_be(:membership) { create_default(:membership) }
  let_it_be(:customer) { create_default(:customer, organization:) }

  before do
    subscription
    wallet_transaction
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", %w[customers:view wallets:create wallets:update wallets:top_up wallets:terminate]

  it "returns a list of wallet transactions" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: described_class::REQUIRED_PERMISSION.sample,
      query:,
      variables: {
        walletId: wallet.id
      }
    )

    wallet_transactions_response = result["data"]["walletTransactions"]

    expect(wallet_transactions_response["collection"].count).to eq(wallet.wallet_transactions.count)
    expect(wallet_transactions_response["collection"].first["id"]).to eq(wallet_transaction.id)

    expect(wallet_transactions_response["metadata"]["currentPage"]).to eq(1)
    expect(wallet_transactions_response["metadata"]["totalCount"]).to eq(1)
  end

  context "without current organization" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        query:,
        variables: {
          walletId: wallet.id
        }
      )

      expect_graphql_error(
        result:,
        message: "Missing organization id"
      )
    end
  end

  context "when not member of the organization" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: create(:organization),
        permissions: described_class::REQUIRED_PERMISSION.sample,
        query:,
        variables: {
          walletId: wallet.id
        }
      )

      expect_graphql_error(
        result:,
        message: "Not in organization"
      )
    end
  end

  context "when wallet does not exists" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: described_class::REQUIRED_PERMISSION.sample,
        query:,
        variables: {
          walletId: "123456"
        }
      )

      expect_graphql_error(
        result:,
        message: "Resource not found"
      )
    end
  end

  context "with N+1 query detection", bullet: {n_plus_one_query: true, unused_eager_loading: false} do
    let(:query) do
      <<~GQL
        query($walletId: ID!) {
          walletTransactions(walletId: $walletId, limit: 5, status: settled) {
            collection {
              id
              wallet { id }
              invoice { id }
              voidedInvoice { id }
              connections { behavior, code }
              selectedInvoiceCustomSections { id }
            }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end

    let(:wallet_transaction_first) { create(:wallet_transaction, wallet:) }
    let(:wallet_transaction_second) { create(:wallet_transaction, wallet:) }

    let(:stripe_connection) { create(:stripe_customer, customer:, organization:, code: "stripe_us", is_default: true) }
    let(:anrok_connection) { create(:anrok_customer, customer:, organization:, code: "anrok_us", is_default: true) }

    before do
      organization.enable_feature_flag!(:multi_connection)

      create(:billing_object_connection, owner: wallet_transaction_first, organization:, category: :payment,
        behavior: :specific, payment_provider_customer: stripe_connection)
      create(:billing_object_connection, owner: wallet_transaction_second, organization:, category: :tax,
        behavior: :specific, integration_customer: anrok_connection)
      create(:billing_object_connection, owner: wallet_transaction_first, organization:, category: :crm, behavior: :skip)
    end

    it "renders wallet transactions without N+1 queries" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: described_class::REQUIRED_PERMISSION.sample,
        query:,
        variables: {
          walletId: wallet.id
        }
      )

      wallet_transactions_response = result["data"]["walletTransactions"]
      expect(wallet_transactions_response["collection"].count).to eq(3)
    end
  end
end
