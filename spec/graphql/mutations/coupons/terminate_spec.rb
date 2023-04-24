# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Coupons::Terminate, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:coupon) { create(:coupon, organization:) }

  let(:mutation) do
    <<-GQL
      mutation($input: TerminateCouponInput!) {
        terminateCoupon(input: $input) {
          id name status terminatedAt
        }
      }
    GQL
  end

  it 'terminates a coupon' do
    result = execute_graphql(
      current_user: membership.user,
      query: mutation,
      variables: {
        input: { id: coupon.id },
      },
    )

    data = result['data']['terminateCoupon']
    expect(data['id']).to eq(coupon.id)
    expect(data['name']).to eq(coupon.name)
    expect(data['status']).to eq('terminated')
    expect(data['terminatedAt']).to be_present
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
