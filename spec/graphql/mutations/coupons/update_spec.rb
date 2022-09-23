# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Coupons::Update, type: :graphql do
  let(:membership) { create(:membership) }
  let(:coupon) { create(:coupon, organization: membership.organization) }
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
          expirationDuration
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
          expirationDuration: 33,
        },
      },
    )

    result_data = result['data']['updateCoupon']

    aggregate_failures do
      expect(result_data['name']).to eq('New name')
      expect(result_data['code']).to eq('new_code')
      expect(result_data['status']).to eq('active')
      expect(result_data['amountCents']).to eq(123)
      expect(result_data['amountCurrency']).to eq('USD')
      expect(result_data['expiration']).to eq('time_limit')
      expect(result_data['expirationDuration']).to eq(33)
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
            expirationDuration: 33,
          },
        },
      )

      expect_unauthorized_error(result)
    end
  end
end
