# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wallets::CreateService, type: :service do
  subject(:create_service) { described_class.new(params:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:, external_id: 'foobar', currency: customer_currency) }
  let(:customer_currency) { 'EUR' }

  describe '#call' do
    let(:paid_credits) { '1.00' }
    let(:granted_credits) { '0.00' }
    let(:expiration_at) { (Time.current + 1.year).iso8601 }

    let(:params) do
      {
        name: 'New Wallet',
        customer:,
        organization_id: organization.id,
        currency: 'EUR',
        rate_amount: '1.00',
        expiration_at:,
        paid_credits:,
        granted_credits:
      }
    end

    let(:service_result) { create_service.call }

    it 'creates a wallet' do
      aggregate_failures do
        expect { service_result }.to change(Wallet, :count).by(1)

        expect(service_result).to be_success

        wallet = service_result.wallet
        expect(wallet.customer_id).to eq(customer.id)
        expect(wallet.name).to eq('New Wallet')
        expect(wallet.currency).to eq('EUR')
        expect(wallet.rate_amount).to eq(1.0)
        expect(wallet.expiration_at.iso8601).to eq(expiration_at)
        expect(wallet.recurring_transaction_rules.count).to eq(0)
      end
    end

    it 'enqueues the WalletTransaction::CreateJob' do
      expect { service_result }
        .to have_enqueued_job(WalletTransactions::CreateJob)
    end

    context 'with validation error' do
      let(:paid_credits) { '-15.00' }

      it 'returns an error' do
        expect(service_result).not_to be_success
        expect(service_result.error.messages[:paid_credits]).to eq(['invalid_paid_credits'])
      end
    end

    context 'when customer does not have a currency' do
      let(:customer_currency) { nil }

      it 'applies the currency to the customer' do
        service_result
        expect(customer.reload.currency).to eq('EUR')
      end
    end

    context 'with recurring transaction rules' do
      around { |test| lago_premium!(&test) }

      let(:rules) do
        [
          {
            interval: "monthly",
            method: "target",
            paid_credits: "10.0",
            granted_credits: "5.0",
            target_ongoing_balance: "100.0",
            trigger: "interval"
          }
        ]
      end
      let(:params) do
        {
          name: 'New Wallet',
          customer:,
          organization_id: organization.id,
          currency: 'EUR',
          rate_amount: '1.00',
          expiration_at:,
          paid_credits:,
          granted_credits:,
          recurring_transaction_rules: rules
        }
      end

      it 'creates a wallet with recurring transaction rules' do
        aggregate_failures do
          expect { service_result }.to change(Wallet, :count).by(1)

          expect(service_result).to be_success
          wallet = service_result.wallet
          expect(wallet.name).to eq('New Wallet')
          expect(wallet.reload.recurring_transaction_rules.count).to eq(1)
        end
      end

      context 'when number of rules is incorrect' do
        let(:rules) do
          [
            {
              trigger: 'interval',
              interval: 'monthly'
            },
            {
              trigger: 'threshold',
              threshold_credits: '1.0'
            }
          ]
        end

        it 'returns an error' do
          expect(service_result).not_to be_success
          expect(service_result.error.messages[:recurring_transaction_rules])
            .to eq(['invalid_number_of_recurring_rules'])
        end
      end

      context 'when trigger is invalid' do
        let(:rules) do
          [
            {
              trigger: 'invalid',
              interval: 'monthly'
            }
          ]
        end

        it 'returns an error' do
          expect(service_result).not_to be_success
          expect(service_result.error.messages[:recurring_transaction_rules]).to eq(['invalid_recurring_rule'])
        end
      end

      context 'when threshold credits value is invalid' do
        let(:rules) do
          [
            {
              trigger: 'threshold',
              threshold_credits: 'abc'
            }
          ]
        end

        it 'returns an error' do
          expect(service_result).not_to be_success
          expect(service_result.error.messages[:recurring_transaction_rules]).to eq(['invalid_recurring_rule'])
        end
      end
    end
  end
end
