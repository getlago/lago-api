# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wallets::CreateService, type: :service do
  subject(:create_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization: organization, external_id: 'foobar', currency: customer_currency) }
  let(:customer_currency) { 'EUR' }

  describe '.create' do
    let(:paid_credits) { '1.00' }
    let(:granted_credits) { '0.00' }

    let(:create_args) do
      {
        name: 'New Wallet',
        customer: customer,
        organization_id: organization.id,
        currency: 'EUR',
        rate_amount: '1.00',
        expiration_at: DateTime.parse('2022-01-01 23:59:59'),
        paid_credits: paid_credits,
        granted_credits: granted_credits,
      }
    end

    let(:service_result) { create_service.create(**create_args) }

    it 'creates a wallet' do
      aggregate_failures do
        expect { service_result }.to change(Wallet, :count).by(1)

        expect(service_result).to be_success

        wallet = service_result.wallet
        expect(wallet.customer_id).to eq(customer.id)
        expect(wallet.name).to eq('New Wallet')
        expect(wallet.currency).to eq('EUR')
        expect(wallet.rate_amount).to eq(1.0)
        expect(wallet.expiration_at.iso8601).to eq('2022-01-01T23:59:59Z')
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
        create_service.create(**create_args)

        expect(customer.reload.currency).to eq('EUR')
      end
    end
  end
end
