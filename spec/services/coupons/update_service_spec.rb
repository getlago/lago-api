# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Coupons::UpdateService, type: :service do
  subject(:update_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  let(:coupon) { create(:coupon, organization: organization) }

  describe 'update' do
    before { coupon }

    let(:update_args) do
      {
        id: coupon.id,
        name: 'new name',
        amount_cents: 100,
        amount_currency: 'EUR',
        expiration: 'time_limit',
        expiration_duration: 30,
      }
    end

    it 'updates the coupon' do
      result = update_service.update(**update_args)

      expect(result).to be_success

      aggregate_failures do
        expect(result.coupon.name).to eq('new name')
        expect(result.coupon.amount_cents).to eq(100)
        expect(result.coupon.amount_currency).to eq('EUR')
        expect(result.coupon.expiration).to eq('time_limit')
        expect(result.coupon.expiration_duration).to eq(30)
      end
    end

    context 'with validation error' do
      let(:update_args) do
        {
          id: coupon.id,
          name: nil,
          amount_cents: 100,
          amount_currency: 'EUR',
          expiration: 'time_limit',
          expiration_duration: 30,
        }
      end

      it 'returns an error' do
        result = update_service.update(**update_args)

        expect(result).to_not be_success
        expect(result.error_code).to eq('unprocessable_entity')
      end
    end
  end
end
