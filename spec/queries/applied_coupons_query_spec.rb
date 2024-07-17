# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AppliedCouponsQuery, type: :query do
  subject(:result) do
    described_class.call(organization:, pagination:, filters:)
  end

  let(:organization) { create(:organization) }
  let(:pagination) { BaseQuery::Pagination.new }
  let(:filters) { BaseQuery::Filters.new(query_filters) }

  let(:query_filters) { {} }

  let(:customer) { create(:customer, organization:) }
  let(:coupon) { create(:coupon, organization:) }

  let(:applied_coupon) { create(:applied_coupon, coupon:, customer:) }

  before { applied_coupon }

  it 'returns a list of applied_coupons' do
    aggregate_failures do
      expect(result).to be_success
      expect(result.applied_coupons.count).to eq(1)
      expect(result.applied_coupons).to eq([applied_coupon])
    end
  end

  context 'when customer is deleted' do
    let(:customer) { create(:customer, :deleted, organization:) }

    it 'filters the applied_coupons' do
      aggregate_failures do
        expect(result).to be_success
        expect(result.applied_coupons.count).to eq(0)
      end
    end
  end

  context 'with pagination' do
    let(:pagination) { BaseQuery::Pagination.new(page: 2, limit: 10) }

    it 'applies the pagination' do
      aggregate_failures do
        expect(result).to be_success
        expect(result.applied_coupons.count).to eq(0)
        expect(result.applied_coupons.current_page).to eq(2)
      end
    end
  end

  context 'with customer filter' do
    let(:query_filters) { {external_customer_id: customer.external_id} }

    it 'applies the filter' do
      aggregate_failures do
        expect(result).to be_success
        expect(result.applied_coupons.count).to eq(1)
      end
    end
  end

  context 'with status filter' do
    let(:query_filters) { {status: 'terminated'} }

    it 'applies the filter' do
      aggregate_failures do
        expect(result).to be_success
        expect(result.applied_coupons.count).to eq(0)
      end
    end
  end
end
