# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CouponsQuery, type: :query do
  subject(:coupon_query) do
    described_class.new(organization:)
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:coupon_first) { create(:coupon, organization:, status: 'active', name: 'defgh', code: '11') }
  let(:coupon_second) { create(:coupon, organization:, status: 'terminated', name: 'abcde', code: '22') }
  let(:coupon_third) { create(:coupon, organization:, status: 'active', name: 'presuv', code: '33') }

  before do
    coupon_first
    coupon_second
    coupon_third
  end

  it 'returns all coupons' do
    result = coupon_query.call(
      search_term: nil,
      status: nil,
      page: 1,
      limit: 10
    )

    returned_ids = result.coupons.pluck(:id)

    aggregate_failures do
      expect(result.coupons.count).to eq(3)
      expect(returned_ids).to include(coupon_first.id)
      expect(returned_ids).to include(coupon_second.id)
      expect(returned_ids).to include(coupon_third.id)
    end
  end

  context 'when searching for /de/ term' do
    it 'returns only two coupons' do
      result = coupon_query.call(
        search_term: 'de',
        status: nil,
        page: 1,
        limit: 10
      )

      returned_ids = result.coupons.pluck(:id)

      aggregate_failures do
        expect(result.coupons.count).to eq(2)
        expect(returned_ids).to include(coupon_first.id)
        expect(returned_ids).to include(coupon_second.id)
        expect(returned_ids).not_to include(coupon_third.id)
      end
    end
  end

  context 'when searching for /de/ term and filtering by id' do
    it 'returns only one coupon' do
      result = coupon_query.call(
        search_term: 'de',
        status: nil,
        page: 1,
        limit: 10,
        filters: {
          ids: [coupon_second.id]
        }
      )

      returned_ids = result.coupons.pluck(:id)

      aggregate_failures do
        expect(result.coupons.count).to eq(1)
        expect(returned_ids).not_to include(coupon_first.id)
        expect(returned_ids).to include(coupon_second.id)
        expect(returned_ids).not_to include(coupon_third.id)
      end
    end
  end

  context 'when searching for terminated status' do
    it 'returns only two coupons' do
      result = coupon_query.call(
        search_term: nil,
        status: 'terminated',
        page: 1,
        limit: 10
      )

      returned_ids = result.coupons.pluck(:id)

      aggregate_failures do
        expect(result.coupons.count).to eq(1)
        expect(returned_ids).not_to include(coupon_first.id)
        expect(returned_ids).to include(coupon_second.id)
        expect(returned_ids).not_to include(coupon_third.id)
      end
    end
  end
end
