# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WalletTransactions::CreateService, type: :service do
  subject(:create_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization: organization) }
  let(:subscription) { create(:subscription, customer: customer) }
  let(:wallet) { create(:wallet, customer: customer) }

  before do
    subscription
  end

  describe '.create' do
    let(:paid_credits) { '1.00' }
    let(:granted_credits) { '0.00' }
    let(:create_args) do
      {
        name: 'New Wallet',
        wallet_id: wallet.id,
        customer_id: customer.id,
        paid_credits: paid_credits,
        granted_credits: granted_credits,
      }
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
