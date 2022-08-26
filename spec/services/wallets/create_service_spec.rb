# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wallets::CreateService, type: :service do
  subject(:create_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization: organization, customer_id: 'foobar') }
  let(:subscription) { create(:subscription, customer: customer) }

  before { subscription }

  describe '.create' do
    let(:paid_credits) { '1.00' }
    let(:granted_credits) { '0.00' }
    let(:create_args) do
      {
        name: 'New Wallet',
        customer: customer,
        organization_id: organization.id,
        rate_amount: '1.00',
        expiration_date: '2022-01-01',
        paid_credits: paid_credits,
        granted_credits: granted_credits,
      }
    end

    it 'creates a wallet' do
      expect { create_service.create(**create_args) }
        .to change(Wallet, :count).by(1)
    end

    it 'enqueues the WalletTransaction::CreateJob' do
      expect { create_service.create(**create_args) }
        .to have_enqueued_job(WalletTransactions::CreateJob)
    end

    context 'with validation error' do
      let(:paid_credits) { '-15.00' }

      it 'returns an error' do
        result = create_service.create(**create_args)

        expect(result).not_to be_success
        expect(result.error_details.first).to eq('invalid_paid_credits')
      end
    end
  end
end
