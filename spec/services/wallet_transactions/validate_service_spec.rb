# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WalletTransactions::ValidateService, type: :service do
  subject(:validate_service) { described_class.new(result, **args) }

  let(:result) { BaseService::Result.new }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization: organization) }
  let(:subscription) { create(:subscription, customer: customer) }
  let(:wallet) { create(:wallet, customer: customer) }
  let(:wallet_id) { wallet.id }
  let(:paid_credits) { '1.00' }
  let(:granted_credits) { '0.00' }
  let(:args) do
    {
      wallet_id: wallet_id,
      paid_credits: paid_credits,
      granted_credits: granted_credits,
    }
  end

  before { subscription }

  describe '.valid?' do
    it 'returns true' do
      expect(validate_service).to be_valid
    end

    context 'when wallet does not exists' do
      let(:wallet_id) { '123456' }

      it 'returns false and result has errors' do
        expect(validate_service).not_to be_valid
        expect(result.error_details.first).to eq('wallet_not_found')
      end
    end

    context 'with invalid paid_credits' do
      let(:paid_credits) { 'foobar' }

      it 'returns false and result has errors' do
        expect(validate_service).not_to be_valid
        expect(result.error_details.first).to eq('invalid_paid_credits')
      end
    end

    context 'with invalid granted_credits' do
      let(:granted_credits) { 'foobar' }

      it 'returns false and result has errors' do
        expect(validate_service).not_to be_valid
        expect(result.error_details.first).to eq('invalid_granted_credits')
      end
    end
  end
end
