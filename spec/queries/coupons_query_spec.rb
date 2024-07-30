# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CouponsQuery, type: :query do
  subject(:result) do
    described_class.call(organization:, search_term:, pagination:, filters:)
  end

  let(:pagination) { nil }
  let(:search_term) { nil }
  let(:filters) { {} }
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
    returned_ids = result.coupons.pluck(:id)

    aggregate_failures do
      expect(result.coupons.count).to eq(3)
      expect(returned_ids).to include(coupon_first.id)
      expect(returned_ids).to include(coupon_second.id)
      expect(returned_ids).to include(coupon_third.id)
    end
  end

  context 'with pagination' do
    let(:pagination) { {page: 2, limit: 2} }

    it 'applies the pagination' do
      aggregate_failures do
        expect(result).to be_success
        expect(result.coupons.count).to eq(1)
        expect(result.coupons.current_page).to eq(2)
        expect(result.coupons.prev_page).to eq(1)
        expect(result.coupons.next_page).to be_nil
        expect(result.coupons.total_pages).to eq(2)
        expect(result.coupons.total_count).to eq(3)
      end
    end
  end

  context 'when searching for /de/ term' do
    let(:search_term) { 'de' }

    it 'returns only two coupons' do
      returned_ids = result.coupons.pluck(:id)

      aggregate_failures do
        expect(returned_ids.count).to eq(2)
        expect(returned_ids).to include(coupon_first.id)
        expect(returned_ids).to include(coupon_second.id)
        expect(returned_ids).not_to include(coupon_third.id)
      end
    end
  end

  context 'when filtering by terminated status' do
    let(:filters) { {status: 'terminated'} }

    it 'returns only two coupons' do
      returned_ids = result.coupons.pluck(:id)

      aggregate_failures do
        expect(returned_ids.count).to eq(1)
        expect(returned_ids).not_to include(coupon_first.id)
        expect(returned_ids).to include(coupon_second.id)
        expect(returned_ids).not_to include(coupon_third.id)
      end
    end
  end
end
