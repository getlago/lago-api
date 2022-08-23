# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::WalletTransactionsController, type: :request do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization: organization) }
  let(:subscription) { create(:subscription, customer: customer) }
  let(:wallet) { create(:wallet, customer: customer) }
  let(:wallet_id) { wallet.id }

  before do
    subscription
    wallet
  end

  describe 'create' do
    let(:create_params) do
      {
        wallet_id: wallet_id,
        paid_credits: '10',
        granted_credits: '10'
      }
    end

    it 'creates a wallet transactions' do
      post_with_token(organization, '/api/v1/wallet_transactions', { wallet_transaction: create_params })

      expect(response).to have_http_status(:success)

      result = JSON.parse(response.body, symbolize_names: true)[:wallet_transactions]
      expect(result.count).to eq(2)
      expect(result.first[:lago_id]).to be_present
      expect(result.second[:lago_id]).to be_present
      expect(result.first[:status]).to eq('pending')
      expect(result.second[:status]).to eq('settled')
      expect(result.first[:lago_wallet_id]).to eq(wallet.id)
      expect(result.second[:lago_wallet_id]).to eq(wallet.id)
    end

    context 'when wallet does not exist' do
      let(:wallet_id) { wallet.id + '123' }

      it 'returns unprocessable_entity error' do
        post_with_token(organization, '/api/v1/wallet_transactions', { wallet_transaction: create_params })

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
