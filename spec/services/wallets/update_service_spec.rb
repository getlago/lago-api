# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wallets::UpdateService, type: :service do
  subject(:update_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:) }
  let(:wallet) { create(:wallet, customer:) }

  describe 'update' do
    before do
      subscription
      wallet
    end

    let(:update_args) do
      {
        id: wallet.id,
        name: 'new name',
        expiration_at: DateTime.parse('2022-01-01 23:59:59'),
      }
    end

    it 'updates the wallet' do
      result = update_service.update(wallet:, args: update_args)

      expect(result).to be_success

      aggregate_failures do
        expect(result.wallet.name).to eq('new name')
        expect(result.wallet.expiration_at.iso8601).to eq('2022-01-01T23:59:59Z')
      end
    end

    context 'when wallet is not found' do
      let(:update_args) do
        {
          id: '123456',
          name: 'new name',
          expiration_date: '2022-01-01',
        }
      end

      it 'returns an error' do
        result = update_service.update(wallet: nil, args: update_args)

        expect(result).not_to be_success
        expect(result.error.error_code).to eq('wallet_not_found')
      end
    end
  end
end
