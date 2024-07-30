# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WalletTransactionsQuery, type: :query do
  subject(:result) do
    described_class.call(
      organization:,
      wallet_id: wallet_id,
      pagination:,
      filters:
    )
  end

  let(:wallet_id) { wallet.id }
  let(:pagination) { nil }
  let(:filters) { {} }

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

  it 'returns all wallet transactions for a certain wallet' do
    returned_ids = result.wallet_transactions.pluck(:id)

    aggregate_failures do
      expect(returned_ids.count).to eq(3)
      expect(returned_ids).to include(wallet_transaction_first.id)
      expect(returned_ids).to include(wallet_transaction_second.id)
      expect(returned_ids).to include(wallet_transaction_third.id)
      expect(returned_ids).not_to include(wallet_transaction_fourth.id)
    end
  end

  context 'with pagination' do
    let(:pagination) { {page: 2, limit: 2} }

    it 'applies the pagination' do
      aggregate_failures do
        expect(result).to be_success
        expect(result.wallet_transactions.count).to eq(1)
        expect(result.wallet_transactions.current_page).to eq(2)
        expect(result.wallet_transactions.prev_page).to eq(1)
        expect(result.wallet_transactions.next_page).to be_nil
        expect(result.wallet_transactions.total_pages).to eq(2)
        expect(result.wallet_transactions.total_count).to eq(3)
      end
    end
  end

  context 'when filtering by status' do
    let(:wallet_transaction_third) { create(:wallet_transaction, wallet:, status: 'pending') }

    let(:filters) { {status: 'pending'} }

    it 'returns only one wallet transaction' do
      returned_ids = result.wallet_transactions.pluck(:id)

      aggregate_failures do
        expect(returned_ids.count).to eq(1)
        expect(returned_ids).not_to include(wallet_transaction_first.id)
        expect(returned_ids).not_to include(wallet_transaction_second.id)
        expect(returned_ids).to include(wallet_transaction_third.id)
        expect(returned_ids).not_to include(wallet_transaction_fourth.id)
      end
    end
  end

  context 'when filtering by transaction type' do
    let(:wallet_transaction_third) { create(:wallet_transaction, wallet:, transaction_type: 'outbound') }

    let(:filters) { {transaction_type: 'outbound'} }

    it 'returns only one wallet transaction' do
      returned_ids = result.wallet_transactions.pluck(:id)

      aggregate_failures do
        expect(returned_ids.count).to eq(1)
        expect(returned_ids).not_to include(wallet_transaction_first.id)
        expect(returned_ids).not_to include(wallet_transaction_second.id)
        expect(returned_ids).to include(wallet_transaction_third.id)
        expect(returned_ids).not_to include(wallet_transaction_fourth.id)
      end
    end
  end

  context 'when wallet is not found' do
    let(:wallet_id) { "#{wallet.id}abc" }

    it 'returns not found error' do
      aggregate_failures do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.message).to eq('wallet_not_found')
      end
    end
  end
end
