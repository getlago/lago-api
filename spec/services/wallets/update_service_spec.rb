# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wallets::UpdateService, type: :service do
  subject(:update_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization: organization) }
  let(:subscription) { create(:subscription, customer: customer) }
  let(:wallet) { create(:wallet, customer: customer) }

  describe 'update' do
    before do
      subscription
      wallet
    end

    let(:update_args) do
      {
        id: wallet.id,
        name: 'new name',
        expiration_date: '2022-01-01',
      }
    end

    it 'updates the wallet' do
      result = update_service.update(**update_args)

      expect(result).to be_success

      aggregate_failures do
        expect(result.wallet.name).to eq('new name')
        expect(result.wallet.expiration_date).to eq('2022-01-01')
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
        result = update_service.update(**update_args)

        expect(result).not_to be_success
        expect(result.error_code).to eq('not_found')
      end
    end
  end
end
