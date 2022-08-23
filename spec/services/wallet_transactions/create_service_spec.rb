# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WalletTransactions::CreateService, type: :service do
  subject(:create_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization: organization) }
  let(:subscription) { create(:subscription, customer: customer) }
  let(:wallet) { create(:wallet, customer: customer, balance: 10.0, credits_balance: 10.0) }

  before do
    subscription
  end

  describe '.create' do
    let(:paid_credits) { '10.00' }
    let(:granted_credits) { '15.00' }
    let(:create_args) do
      {
        wallet_id: wallet.id,
        organization_id: organization.id,
        paid_credits: paid_credits,
        granted_credits: granted_credits,
      }
    end

    it 'creates a wallet transactions' do
      expect { create_service.create(**create_args) }
        .to change(WalletTransaction, :count).by(2)
    end

    it 'enqueues the BillPaidCreditJob' do
      expect { create_service.create(**create_args) }
        .to have_enqueued_job(BillPaidCreditJob)
    end

    it 'updates wallet balance only with granted credits' do
      create_service.create(**create_args)

      expect(wallet.reload.balance).to eq(25.0)
      expect(wallet.reload.credits_balance).to eq(25.0)
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
