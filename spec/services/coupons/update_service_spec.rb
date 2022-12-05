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
        coupon_type: 'fixed_amount',
        frequency: 'once',
        amount_cents: 100,
        amount_currency: 'EUR',
        expiration: 'time_limit',
        reusable: false,
        expiration_date: (Time.current + 30.days).to_date,
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
        expect(result.coupon.reusable).to eq(false)
        expect(result.coupon.expiration_date).to eq (Time.current + 30.days).to_date
      end
    end

    context 'with validation error' do
      let(:update_args) do
        {
          id: coupon.id,
          name: nil,
          coupon_type: 'fixed_amount',
          frequency: 'once',
          amount_cents: 100,
          amount_currency: 'EUR',
          reusable: false,
          expiration: 'time_limit',
          expiration_date: (Time.current + 30.days).to_date,
        }
      end

      it 'returns an error' do
        result = update_service.update(**update_args)

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:name]).to eq(['value_is_mandatory'])
        end
      end
    end
  end

  describe 'update_from_api' do
    let(:coupon) { create(:coupon, organization: organization) }
    let(:name) { 'New Coupon' }
    let(:update_args) do
      {
        name: name,
        code: 'coupon1_code',
        coupon_type: 'fixed_amount',
        frequency: 'once',
        amount_cents: 123,
        amount_currency: 'EUR',
        expiration: 'time_limit',
        expiration_date: (Time.current + 15.days).to_date,
      }
    end

    it 'updates the coupon' do
      result = subject.update_from_api(
        organization: organization,
        code: coupon.code,
        params: update_args,
      )

      aggregate_failures do
        expect(result).to be_success

        coupon_result = result.coupon
        expect(coupon_result.id).to eq(coupon.id)
        expect(coupon_result.name).to eq(update_args[:name])
        expect(coupon_result.code).to eq(update_args[:code])
        expect(coupon_result.expiration).to eq(update_args[:expiration])
      end
    end

    context 'with validation errors' do
      let(:name) { nil }

      it 'returns an error' do
        result = subject.update_from_api(
          organization: organization,
          code: coupon.code,
          params: update_args,
        )

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:name]).to eq(['value_is_mandatory'])
        end
      end
    end

    context 'when coupon is not found' do
      it 'returns an error' do
        result = subject.update_from_api(
          organization: organization,
          code: 'fake_code12345',
          params: update_args,
        )

        expect(result).not_to be_success
        expect(result.error.error_code).to eq('coupon_not_found')
      end
    end
  end
end
