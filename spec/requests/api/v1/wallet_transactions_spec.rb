# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::WalletTransactionsController, type: :request do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:) }
  let(:wallet) { create(:wallet, customer:) }
  let(:wallet_id) { wallet.id }

  before do
    subscription
    wallet
  end

  describe 'create' do
    let(:create_params) do
      {
        wallet_id:,
        paid_credits: '10',
        granted_credits: '10',
      }
    end

    it 'creates a wallet transactions' do
      post_with_token(organization, '/api/v1/wallet_transactions', { wallet_transaction: create_params })

      expect(response).to have_http_status(:success)

      expect(json[:wallet_transactions].count).to eq(2)
      expect(json[:wallet_transactions].first[:lago_id]).to be_present
      expect(json[:wallet_transactions].second[:lago_id]).to be_present
      expect(json[:wallet_transactions].first[:status]).to eq('pending')
      expect(json[:wallet_transactions].second[:status]).to eq('settled')
      expect(json[:wallet_transactions].first[:lago_wallet_id]).to eq(wallet.id)
      expect(json[:wallet_transactions].second[:lago_wallet_id]).to eq(wallet.id)
    end

    context 'when wallet does not exist' do
      let(:wallet_id) { "#{wallet.id}123" }

      it 'returns unprocessable_entity error' do
        post_with_token(organization, '/api/v1/wallet_transactions', { wallet_transaction: create_params })

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'index' do
    let(:wallet_transaction_first) { create(:wallet_transaction, wallet:) }
    let(:wallet_transaction_second) { create(:wallet_transaction, wallet:) }
    let(:wallet_transaction_third) { create(:wallet_transaction) }

    before do
      wallet_transaction_first
      wallet_transaction_second
      wallet_transaction_third
    end

    it 'returns wallet transactions' do
      get_with_token(organization, "/api/v1/wallets/#{wallet_id}/wallet_transactions")

      expect(response).to have_http_status(:success)
      expect(json[:wallet_transactions].count).to eq(2)
      expect(json[:wallet_transactions].first[:lago_id]).to eq(wallet_transaction_second.id)
      expect(json[:wallet_transactions].last[:lago_id]).to eq(wallet_transaction_first.id)
    end

    context 'with pagination' do
      it 'returns wallet transactions with correct meta data' do
        get_with_token(organization, "/api/v1/wallets/#{wallet_id}/wallet_transactions?page=1&per_page=1")

        expect(response).to have_http_status(:success)

        expect(json[:wallet_transactions].count).to eq(1)
        expect(json[:meta][:current_page]).to eq(1)
        expect(json[:meta][:next_page]).to eq(2)
        expect(json[:meta][:prev_page]).to eq(nil)
        expect(json[:meta][:total_pages]).to eq(2)
        expect(json[:meta][:total_count]).to eq(2)
      end
    end

    context 'with status param' do
      let(:wallet_transaction_second) { create(:wallet_transaction, wallet:, status: 'pending') }

      it 'returns wallet transactions with correct status' do
        get_with_token(organization, "/api/v1/wallets/#{wallet_id}/wallet_transactions?status=pending")

        expect(response).to have_http_status(:success)
        expect(json[:wallet_transactions].count).to eq(1)
        expect(json[:wallet_transactions].first[:lago_id]).to eq(wallet_transaction_second.id)
      end
    end

    context 'with transaction type param' do
      let(:wallet_transaction_second) { create(:wallet_transaction, wallet:, transaction_type: 'outbound') }

      it 'returns wallet transactions with correct transaction type' do
        get_with_token(organization, "/api/v1/wallets/#{wallet_id}/wallet_transactions?transaction_type=outbound")

        expect(response).to have_http_status(:success)
        expect(json[:wallet_transactions].count).to eq(1)
        expect(json[:wallet_transactions].first[:lago_id]).to eq(wallet_transaction_second.id)
      end
    end

    context 'when wallet does not exist' do
      let(:wallet_id) { "#{wallet.id}abc" }

      it 'returns not_found error' do
        get_with_token(organization, "/api/v1/wallets/#{wallet_id}/wallet_transactions")

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
