# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::CouponResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query($couponId: ID!) {
        coupon(id: $couponId) {
          id, name, customerCount expirationDate
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:coupon) { create(:coupon, organization: organization) }

  it 'returns a single coupon' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query: query,
      variables: {
        couponId: coupon.id,
      },
    )

    coupon_response = result['data']['coupon']

    aggregate_failures do
      expect(coupon_response['id']).to eq(coupon.id)
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        query: query,
        variables: {
          couponId: coupon.id,
        },
      )

      expect_graphql_error(
        result: result,
        message: 'Missing organization id',
      )
    end
  end

  context 'when plan is not found' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query: query,
        variables: {
          couponId: 'foo',
        },
      )

      expect_graphql_error(
        result: result,
        message: 'Resource not found',
      )
    end
  end
end
