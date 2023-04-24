# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::CouponsResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query {
        coupons(limit: 5, status: active) {
          collection { id }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:coupon) { create(:coupon, organization:) }

  before do
    coupon

    create(:coupon, organization:, status: :terminated)
  end

  it 'returns a list of coupons' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query:,
    )

    coupons_response = result['data']['coupons']

    aggregate_failures do
      expect(coupons_response['collection'].count).to eq(organization.coupons.active.count)
      expect(coupons_response['collection'].first['id']).to eq(coupon.id)

      expect(coupons_response['metadata']['currentPage']).to eq(1)
      expect(coupons_response['metadata']['totalCount']).to eq(1)
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(current_user: membership.user, query:)

      expect_graphql_error(
        result:,
        message: 'Missing organization id',
      )
    end
  end

  context 'when not member of the organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: create(:organization),
        query:,
      )

      expect_graphql_error(
        result:,
        message: 'Not in organization',
      )
    end
  end
end
