# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Coupons::Destroy, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:coupon) { create(:coupon, organization:) }

  let(:mutation) do
    <<-GQL
      mutation($input: DestroyCouponInput!) {
        destroyCoupon(input: $input) { id }
      }
    GQL
  end

  it 'deletes a coupon' do
    result = execute_graphql(
      current_user: membership.user,
      query: mutation,
      variables: {
        input: { id: coupon.id },
      },
    )

    data = result['data']['destroyCoupon']
    expect(data['id']).to eq(coupon.id)
  end

  context 'without current_user' do
    it 'returns an error' do
      result = execute_graphql(
        query: mutation,
        variables: {
          input: { id: coupon.id },
        },
      )

      expect_unauthorized_error(result)
    end
  end
end
