# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Coupons::Update, type: :graphql do
  let(:membership) { create(:membership) }
  let(:coupon) { create(:coupon, organization: membership.organization) }
  let(:expiration_at) { Time.current + 3.days }
  let(:mutation) do
    <<-GQL
      mutation($input: UpdateCouponInput!) {
        updateCoupon(input: $input) {
          id,
          name,
          code,
          status,
          amountCents,
          amountCurrency,
          expiration,
          expirationAt,
          reusable
        }
      }
    GQL
  end

  it 'updates a coupon' do
    result = execute_graphql(
      current_user: membership.user,
      query: mutation,
      variables: {
        input: {
          id: coupon.id,
          name: 'New name',
          couponType: 'fixed_amount',
          frequency: 'once',
          code: 'new_code',
          amountCents: 123,
          amountCurrency: 'USD',
          expiration: 'time_limit',
          expirationAt: expiration_at.iso8601,
          reusable: false,
        },
      },
    )

    result_data = result['data']['updateCoupon']

    aggregate_failures do
      expect(result_data['name']).to eq('New name')
      expect(result_data['code']).to eq('new_code')
      expect(result_data['status']).to eq('active')
      expect(result_data['amountCents']).to eq('123')
      expect(result_data['amountCurrency']).to eq('USD')
      expect(result_data['expiration']).to eq('time_limit')
      expect(result_data['expirationAt']).to eq expiration_at.iso8601
      expect(result_data['reusable']).to eq(false)
    end
  end

  context 'without current_user' do
    it 'returns an error' do
      result = execute_graphql(
        query: mutation,
        variables: {
          input: {
            id: coupon.id,
            name: 'New name',
            code: 'new_code',
            couponType: 'fixed_amount',
            frequency: 'once',
            amountCents: 123,
            amountCurrency: 'USD',
            expiration: 'time_limit',
            expirationAt: (Time.current + 33.days).iso8601,
          },
        },
      )

      expect_unauthorized_error(result)
    end
  end
end
