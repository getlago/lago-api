# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::WalletsController, type: :request do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, currency: 'EUR') }
  let(:subscription) { create(:subscription, customer:) }
  let(:expiration_at) { (Time.current + 1.year).iso8601 }

  before { subscription }

  describe 'create' do
    let(:create_params) do
      {
        external_customer_id: customer.external_id,
        rate_amount: '1',
        name: 'Wallet1',
        currency: 'EUR',
        paid_credits: '10',
        granted_credits: '10',
        expiration_at:
      }
    end

    it 'creates a wallet' do
      post_with_token(organization, '/api/v1/wallets', {wallet: create_params})

      aggregate_failures do
        expect(response).to have_http_status(:success)

        expect(json[:wallet][:lago_id]).to be_present
        expect(json[:wallet][:name]).to eq(create_params[:name])
        expect(json[:wallet][:external_customer_id]).to eq(customer.external_id)
        expect(json[:wallet][:expiration_at]).to eq(expiration_at)
      end
    end

    context 'with recurring transaction rules' do
      around { |test| lago_premium!(&test) }

      let(:create_params) do
        {
          external_customer_id: customer.external_id,
          rate_amount: '1',
          name: 'Wallet1',
          currency: 'EUR',
          paid_credits: '10',
          granted_credits: '10',
          expiration_at:,
          recurring_transaction_rules: [
            {
              trigger: 'interval',
              interval: 'monthly'
            }
          ]
        }
      end

      it 'returns a success' do
        post_with_token(organization, '/api/v1/wallets', {wallet: create_params})

        recurring_rules = json[:wallet][:recurring_transaction_rules]

        aggregate_failures do
          expect(response).to have_http_status(:success)

          expect(recurring_rules).to be_present
          expect(recurring_rules.first[:interval]).to eq('monthly')
          expect(recurring_rules.first[:paid_credits]).to eq('10.0')
          expect(recurring_rules.first[:granted_credits]).to eq('10.0')
          expect(recurring_rules.first[:method]).to eq('fixed')
          expect(recurring_rules.first[:trigger]).to eq('interval')
        end
      end
    end
  end

  describe 'update' do
    let(:wallet) { create(:wallet, customer:) }
    let(:expiration_at) { (Time.current + 1.year).iso8601 }
    let(:update_params) do
      {
        name: 'wallet1',
        expiration_at:
      }
    end

    before { wallet }

    it 'updates a wallet' do
      put_with_token(
        organization,
        "/api/v1/wallets/#{wallet.id}",
        {wallet: update_params}
      )

      aggregate_failures do
        expect(response).to have_http_status(:success)

        expect(json[:wallet][:lago_id]).to eq(wallet.id)
        expect(json[:wallet][:name]).to eq(update_params[:name])
        expect(json[:wallet][:expiration_at]).to eq(expiration_at)
      end
    end

    context 'when wallet does not exist' do
      it 'returns not_found error' do
        put_with_token(organization, '/api/v1/wallets/invalid', {wallet: update_params})

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'with recurring transaction rules' do
      around { |test| lago_premium!(&test) }

      let(:recurring_transaction_rule) { create(:recurring_transaction_rule, wallet:) }
      let(:update_params) do
        {
          name: 'wallet1',
          recurring_transaction_rules: [
            {
              lago_id: recurring_transaction_rule.id,
              method: 'target',
              trigger: 'interval',
              interval: 'weekly',
              paid_credits: '105',
              granted_credits: '105',
              target_ongoing_balance: '300'
            }
          ]
        }
      end

      before { recurring_transaction_rule }

      it 'returns a success' do
        put_with_token(
          organization,
          "/api/v1/wallets/#{wallet.id}",
          {wallet: update_params}
        )

        recurring_rules = json[:wallet][:recurring_transaction_rules]

        aggregate_failures do
          expect(response).to have_http_status(:success)

          expect(recurring_rules).to be_present
          expect(recurring_rules.first[:lago_id]).to eq(recurring_transaction_rule.id)
          expect(recurring_rules.first[:interval]).to eq('weekly')
          expect(recurring_rules.first[:paid_credits]).to eq('105.0')
          expect(recurring_rules.first[:granted_credits]).to eq('105.0')
          expect(recurring_rules.first[:method]).to eq('target')
          expect(recurring_rules.first[:trigger]).to eq('interval')
        end
      end
    end
  end

  describe 'show' do
    let(:wallet) { create(:wallet, customer:) }

    before { wallet }

    it 'returns a wallet' do
      get_with_token(
        organization,
        "/api/v1/wallets/#{wallet.id}"
      )

      expect(response).to have_http_status(:success)
      expect(json[:wallet][:lago_id]).to eq(wallet.id)
      expect(json[:wallet][:name]).to eq(wallet.name)
    end

    context 'when wallet does not exist' do
      it 'returns not found' do
        get_with_token(organization, '/api/v1/wallets/555')

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'terminate' do
    let(:wallet) { create(:wallet, customer:) }

    before { wallet }

    it 'terminates a wallet' do
      delete_with_token(organization, "/api/v1/wallets/#{wallet.id}")

      expect(wallet.reload.status).to eq('terminated')
    end

    it 'returns terminated wallet' do
      delete_with_token(organization, "/api/v1/wallets/#{wallet.id}")

      expect(response).to have_http_status(:success)
      expect(json[:wallet][:lago_id]).to eq(wallet.id)
      expect(json[:wallet][:name]).to eq(wallet.name)
    end

    context 'when wallet does not exist' do
      it 'returns not_found error' do
        delete_with_token(organization, '/api/v1/wallets/invalid')

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when wallet id does not belong to the current organization' do
      it 'returns a not found error' do
        other_wallet = create(:wallet)
        delete_with_token(organization, "/api/v1/wallets/#{other_wallet.id}")

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'index' do
    let(:wallet) { create(:wallet, customer:) }

    before { wallet }

    it 'returns wallets' do
      get_with_token(organization, "/api/v1/wallets?external_customer_id=#{customer.external_id}")

      expect(response).to have_http_status(:success)
      expect(json[:wallets].count).to eq(1)
      expect(json[:wallets].first[:lago_id]).to eq(wallet.id)
      expect(json[:wallets].first[:name]).to eq(wallet.name)
      expect(json[:wallets].first[:recurring_transaction_rules]).to be_empty
    end

    context 'with pagination' do
      let(:wallet2) { create(:wallet, customer:) }

      before { wallet2 }

      it 'returns wallets with correct meta data' do
        get_with_token(organization, "/api/v1/wallets?external_customer_id=#{customer.external_id}&page=1&per_page=1")

        expect(response).to have_http_status(:success)

        expect(json[:wallets].count).to eq(1)
        expect(json[:meta][:current_page]).to eq(1)
        expect(json[:meta][:next_page]).to eq(2)
        expect(json[:meta][:prev_page]).to eq(nil)
        expect(json[:meta][:total_pages]).to eq(2)
        expect(json[:meta][:total_count]).to eq(2)
      end
    end

    context 'when external_customer_id does not belong to the current organization' do
      it 'returns a not found error' do
        other_customer = create(:customer)
        get_with_token(organization, "/api/v1/wallets?external_customer_id=#{other_customer.external_id}")

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
