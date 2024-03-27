# frozen_string_literal: true

require "rails_helper"

RSpec.describe WalletTransactionsQuery, type: :query do
  subject(:wallet_transactions_query) do
    described_class.new(organization:)
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:wallet) { create(:wallet, customer:) }
  let(:wallet_transaction_first) { create(:wallet_transaction, wallet:) }
  let(:wallet_transaction_second) { create(:wallet_transaction, wallet:) }
  let(:wallet_transaction_third) { create(:wallet_transaction, wallet:) }
  let(:wallet_transaction_fourth) { create(:wallet_transaction) }

  before do
    wallet_transaction_first
    wallet_transaction_second
    wallet_transaction_third
    wallet_transaction_fourth
  end

  it "returns all wallet transactions for a certain wallet" do
    result = wallet_transactions_query.call(
      wallet_id: wallet.id,
      page: 1,
      limit: 10,
      filters: {}
    )

    returned_ids = result.wallet_transactions.pluck(:id)

    aggregate_failures do
      expect(result.wallet_transactions.count).to eq(3)
      expect(returned_ids).to include(wallet_transaction_first.id)
      expect(returned_ids).to include(wallet_transaction_second.id)
      expect(returned_ids).to include(wallet_transaction_third.id)
      expect(returned_ids).not_to include(wallet_transaction_fourth.id)
    end
  end

  context "when filtering by id" do
    it "returns only one wallet transaction" do
      result = wallet_transactions_query.call(
        wallet_id: wallet.id,
        page: 1,
        limit: 10,
        filters: {
          ids: [wallet_transaction_second.id]
        }
      )

      returned_ids = result.wallet_transactions.pluck(:id)

      aggregate_failures do
        expect(result.wallet_transactions.count).to eq(1)
        expect(returned_ids).not_to include(wallet_transaction_first.id)
        expect(returned_ids).to include(wallet_transaction_second.id)
        expect(returned_ids).not_to include(wallet_transaction_third.id)
        expect(returned_ids).not_to include(wallet_transaction_fourth.id)
      end
    end
  end

  context "when filtering by status" do
    let(:wallet_transaction_third) { create(:wallet_transaction, wallet:, status: "pending") }

    it "returns only one wallet transaction" do
      result = wallet_transactions_query.call(
        wallet_id: wallet.id,
        page: 1,
        limit: 10,
        filters: {
          status: "pending"
        }
      )

      returned_ids = result.wallet_transactions.pluck(:id)

      aggregate_failures do
        expect(result.wallet_transactions.count).to eq(1)
        expect(returned_ids).not_to include(wallet_transaction_first.id)
        expect(returned_ids).not_to include(wallet_transaction_second.id)
        expect(returned_ids).to include(wallet_transaction_third.id)
        expect(returned_ids).not_to include(wallet_transaction_fourth.id)
      end
    end
  end

  context "when filtering by transaction type" do
    let(:wallet_transaction_third) { create(:wallet_transaction, wallet:, transaction_type: "outbound") }

    it "returns only one wallet transaction" do
      result = wallet_transactions_query.call(
        wallet_id: wallet.id,
        page: 1,
        limit: 10,
        filters: {
          transaction_type: "outbound"
        }
      )

      returned_ids = result.wallet_transactions.pluck(:id)

      aggregate_failures do
        expect(result.wallet_transactions.count).to eq(1)
        expect(returned_ids).not_to include(wallet_transaction_first.id)
        expect(returned_ids).not_to include(wallet_transaction_second.id)
        expect(returned_ids).to include(wallet_transaction_third.id)
        expect(returned_ids).not_to include(wallet_transaction_fourth.id)
      end
    end
  end

  context "when wallet is not found" do
    it "returns not found error" do
      result = wallet_transactions_query.call(
        wallet_id: "#{wallet.id}abc",
        page: 1,
        limit: 10,
        filters: {}
      )

      aggregate_failures do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.message).to eq("wallet_not_found")
      end
    end
  end
end
