# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wallets::CreateService, type: :service do
  subject(:create_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization: organization) }
  let(:subscription) { create(:subscription, customer: customer) }

  before { subscription }

  describe 'create' do
    let(:create_args) do
      {
        name: 'New Wallet',
        customer_id: customer.id,
        organization_id: organization.id,
        rate_amount: '1.00',
        expiration_date: '2022-01-01',
      }
    end

    it 'creates a wallet' do
      expect { create_service.create(**create_args) }
        .to change(Wallet, :count).by(1)
    end

    context 'with validation error' do
      context 'with already existing active wallet' do
        before do
          create(
            :wallet,
            customer: customer,
          )
        end

        it 'returns an error' do
          result = create_service.create(**create_args)

          expect(result).not_to be_success
          expect(result.error_code).to eq('wallet_already_exists')
        end
      end

      context 'with unknown customer' do
        let(:create_args) do
          {
            name: 'New Wallet',
            customer_id: '123456',
            organization_id: organization.id,
            rate_amount: '1.00',
            expiration_date: '2022-01-01',
          }
        end

        it 'returns an error' do
          result = create_service.create(**create_args)

          expect(result).not_to be_success
          expect(result.error_code).to eq('missing_argument')
        end
      end

      context 'with no active subscription for customer' do
        before { subscription.mark_as_terminated! }

        it 'returns an error' do
          result = create_service.create(**create_args)

          expect(result).not_to be_success
          expect(result.error_code).to eq('no_active_subscription')
        end
      end
    end
  end
end
