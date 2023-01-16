# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Coupons::Create, type: :graphql do
  let(:membership) { create(:membership) }
  let(:expiration_at) { Time.current + 3.days }
  let(:mutation) do
    <<-GQL
      mutation($input: CreateCouponInput!) {
        createCoupon(input: $input) {
          id,
          name,
          code,
          amountCents,
          amountCurrency,
          expiration,
          expirationAt,
          status,
          reusable
        }
      }
    GQL
  end

  it 'creates a coupon' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      query: mutation,
      variables: {
        input: {
          name: 'Super Coupon',
          code: 'free-beer',
          couponType: 'fixed_amount',
          frequency: 'once',
          amountCents: 5000,
          amountCurrency: 'EUR',
          expiration: 'time_limit',
          expirationAt: expiration_at.iso8601,
          reusable: false,
        },
      },
    )

    result_data = result['data']['createCoupon']

    aggregate_failures do
      expect(result_data['id']).to be_present
      expect(result_data['name']).to eq('Super Coupon')
      expect(result_data['code']).to eq('free-beer')
      expect(result_data['amountCents']).to eq('5000')
      expect(result_data['amountCurrency']).to eq('EUR')
      expect(result_data['expiration']).to eq('time_limit')
      expect(result_data['expirationAt']).to eq expiration_at.iso8601
      expect(result_data['status']).to eq('active')
      expect(result_data['reusable']).to eq(false)
    end
  end

  context 'with an expiration date' do
    it 'creates a coupon' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        query: mutation,
        variables: {
          input: {
            name: 'Super Coupon',
            code: 'free-beer',
            couponType: 'fixed_amount',
            frequency: 'once',
            amountCents: 5000,
            amountCurrency: 'EUR',
            expiration: 'time_limit',
            expirationAt: expiration_at.iso8601,
          },
        },
      )

      result_data = result['data']['createCoupon']

      aggregate_failures do
        expect(result_data['id']).to be_present
        expect(result_data['name']).to eq('Super Coupon')
        expect(result_data['code']).to eq('free-beer')
        expect(result_data['amountCents']).to eq('5000')
        expect(result_data['amountCurrency']).to eq('EUR')
        expect(result_data['expiration']).to eq('time_limit')
        expect(result_data['expirationAt']).to eq(expiration_at.iso8601)
        expect(result_data['status']).to eq('active')
      end
    end
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        current_organization: membership.organization,
        query: mutation,
        variables: {
          input: {
            name: 'Super Coupon',
            code: 'free-beer',
            couponType: 'fixed_amount',
            frequency: 'once',
            amountCents: 5000,
            amountCurrency: 'EUR',
            expiration: 'time_limit',
            expirationAt: (Time.current + 3.days).iso8601,
          },
        },
      )

      expect_unauthorized_error(result)
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        query: mutation,
        variables: {
          input: {
            name: 'Super Coupon',
            code: 'free-beer',
            couponType: 'fixed_amount',
            frequency: 'once',
            amountCents: 5000,
            amountCurrency: 'EUR',
            expiration: 'time_limit',
            expirationAt: (Time.current + 3.days).iso8601,
          },
        },
      )

      expect_forbidden_error(result)
    end
  end
end
