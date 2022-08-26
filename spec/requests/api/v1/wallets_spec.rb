# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::WalletsController, type: :request do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization: organization) }
  let(:subscription) { create(:subscription, customer: customer) }

  before { subscription }

  describe 'create' do
    let(:create_params) do
      {
        customer_id: customer.customer_id,
        rate_amount: '1',
        name: 'Wallet1',
        paid_credits: '10',
        granted_credits: '10',
        expiration_date: '2022-06-06'
      }
    end

    it 'creates a wallet' do
      post_with_token(organization, '/api/v1/wallets', { wallet: create_params })

      expect(response).to have_http_status(:success)

      result = JSON.parse(response.body, symbolize_names: true)[:wallet]
      expect(result[:lago_id]).to be_present
      expect(result[:name]).to eq(create_params[:name])
    end
  end

  describe 'update' do
    let(:wallet) { create(:wallet, customer: customer) }
    let(:update_params) do
      {
        name: 'wallet1',
        expiration_date: '2022-07-07'
      }
    end

    before { wallet }

    it 'updates a wallet' do
      put_with_token(organization,
        "/api/v1/wallets/#{wallet.id}",
        { wallet: update_params }
      )

      expect(response).to have_http_status(:success)

      result = JSON.parse(response.body, symbolize_names: true)[:wallet]

      expect(result[:lago_id]).to eq(wallet.id)
      expect(result[:name]).to eq(update_params[:name])
    end

    context 'when wallet does not exist' do
      it 'returns not_found error' do
        put_with_token(organization, '/api/v1/wallets/invalid', { wallet: update_params })

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'show' do
    let(:wallet) { create(:wallet, customer: customer) }

    before { wallet }

    it 'returns a wallet' do
      get_with_token(
        organization,
        "/api/v1/wallets/#{wallet.id}"
      )

      expect(response).to have_http_status(:success)

      result = JSON.parse(response.body, symbolize_names: true)[:wallet]

      expect(result[:lago_id]).to eq(wallet.id)
      expect(result[:name]).to eq(wallet.name)
    end

    context 'when wallet does not exist' do
      it 'returns not found' do
        get_with_token(
          organization,
          "/api/v1/wallets/555"
        )

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'terminate' do
    let(:wallet) { create(:wallet, customer: customer) }

    before { wallet }

    it 'terminates a wallet' do
      delete_with_token(organization, "/api/v1/wallets/#{wallet.id}")

      expect(wallet.reload.status).to eq('terminated')
    end

    it 'returns terminated wallet' do
      delete_with_token(organization, "/api/v1/wallets/#{wallet.id}")

      expect(response).to have_http_status(:success)

      result = JSON.parse(response.body, symbolize_names: true)[:wallet]

      expect(result[:lago_id]).to eq(wallet.id)
      expect(result[:name]).to eq(wallet.name)
    end

    context 'when wallet does not exist' do
      it 'returns not_found error' do
        delete_with_token(organization, '/api/v1/wallets/invalid')

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'index' do
    let(:wallet) { create(:wallet, customer: customer) }

    before { wallet }

    it 'returns wallets' do
      get_with_token(organization, "/api/v1/wallets?customer_id=#{customer.customer_id}")

      expect(response).to have_http_status(:success)

      records = JSON.parse(response.body, symbolize_names: true)[:wallets]

      expect(records.count).to eq(1)
      expect(records.first[:lago_id]).to eq(wallet.id)
      expect(records.first[:name]).to eq(wallet.name)
    end

    context 'with pagination' do
      let(:wallet2) { create(:wallet, customer: customer) }

      before { wallet2 }

      it 'returns wallets with correct meta data' do
        get_with_token(organization, "/api/v1/wallets?customer_id=#{customer.customer_id}&page=1&per_page=1")

        expect(response).to have_http_status(:success)

        response_body = JSON.parse(response.body, symbolize_names: true)

        expect(response_body[:wallets].count).to eq(1)
        expect(response_body[:meta][:current_page]).to eq(1)
        expect(response_body[:meta][:next_page]).to eq(2)
        expect(response_body[:meta][:prev_page]).to eq(nil)
        expect(response_body[:meta][:total_pages]).to eq(2)
        expect(response_body[:meta][:total_count]).to eq(2)
      end
    end
  end
end
