# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::CouponsController, type: :request do
  let(:organization) { create(:organization) }

  describe 'create' do
    let(:billable_metric) { create(:billable_metric, organization:) }
    let(:expiration_at) { Time.current + 15.days }

    let(:create_params) do
      {
        name: 'coupon1',
        code: 'coupon1_code',
        coupon_type: 'fixed_amount',
        frequency: 'once',
        amount_cents: 123,
        amount_currency: 'EUR',
        expiration: 'time_limit',
        expiration_at:,
        reusable: false,
        applies_to: {
          billable_metric_codes: [billable_metric.code]
        }
      }
    end

    it 'creates a coupon' do
      post_with_token(organization, '/api/v1/coupons', {coupon: create_params})

      expect(response).to have_http_status(:success)
      expect(json[:coupon][:lago_id]).to be_present
      expect(json[:coupon][:code]).to eq(create_params[:code])
      expect(json[:coupon][:name]).to eq(create_params[:name])
      expect(json[:coupon][:created_at]).to be_present
      expect(json[:coupon][:expiration_at]).to eq(expiration_at.iso8601)
      expect(json[:coupon][:reusable]).to eq(false)
      expect(json[:coupon][:limited_billable_metrics]).to eq(true)
      expect(json[:coupon][:billable_metric_codes].first).to eq(billable_metric.code)
    end
  end

  describe 'update' do
    let(:coupon) { create(:coupon, organization:) }
    let(:code) { 'coupon_code' }
    let(:expiration_at) { Time.current + 15.days }
    let(:update_params) do
      {
        name: 'coupon1',
        code:,
        coupon_type: 'fixed_amount',
        frequency: 'once',
        amount_cents: 123,
        amount_currency: 'EUR',
        expiration: 'time_limit',
        expiration_at:
      }
    end

    it 'updates a coupon' do
      put_with_token(
        organization,
        "/api/v1/coupons/#{coupon.code}",
        {coupon: update_params}
      )

      expect(response).to have_http_status(:success)
      expect(json[:coupon][:lago_id]).to eq(coupon.id)
      expect(json[:coupon][:code]).to eq(update_params[:code])
      expect(json[:coupon][:expiration_at]).to eq(expiration_at.iso8601)
    end

    context 'when coupon does not exist' do
      it 'returns not_found error' do
        put_with_token(organization, '/api/v1/coupons/invalid', {coupon: update_params})

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when coupon code already exists in organization scope (validation error)' do
      let(:coupon2) { create(:coupon, organization:) }
      let(:code) { coupon2.code }

      before { coupon2 }

      it 'returns unprocessable_entity error' do
        put_with_token(
          organization,
          "/api/v1/coupons/#{coupon.code}",
          {coupon: update_params}
        )

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'show' do
    let(:coupon) { create(:coupon, organization:) }

    it 'returns a coupon' do
      get_with_token(
        organization,
        "/api/v1/coupons/#{coupon.code}"
      )

      expect(response).to have_http_status(:success)
      expect(json[:coupon][:lago_id]).to eq(coupon.id)
      expect(json[:coupon][:code]).to eq(coupon.code)
    end

    context 'when coupon does not exist' do
      it 'returns not found' do
        get_with_token(
          organization,
          '/api/v1/coupons/555'
        )

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'destroy' do
    let(:coupon) { create(:coupon, organization:) }

    before { coupon }

    it 'deletes a coupon' do
      expect { delete_with_token(organization, "/api/v1/coupons/#{coupon.code}") }
        .to change(Coupon, :count).by(-1)
    end

    it 'returns deleted coupon' do
      delete_with_token(organization, "/api/v1/coupons/#{coupon.code}")

      expect(response).to have_http_status(:success)
      expect(json[:coupon][:lago_id]).to eq(coupon.id)
      expect(json[:coupon][:code]).to eq(coupon.code)
    end

    context 'when coupon does not exist' do
      it 'returns not_found error' do
        delete_with_token(organization, '/api/v1/coupons/invalid')

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'index' do
    let(:coupon) { create(:coupon, organization:) }

    before { coupon }

    it 'returns coupons' do
      get_with_token(organization, '/api/v1/coupons')

      expect(response).to have_http_status(:success)
      expect(json[:coupons].count).to eq(1)
      expect(json[:coupons].first[:lago_id]).to eq(coupon.id)
      expect(json[:coupons].first[:code]).to eq(coupon.code)
    end

    context 'with pagination' do
      let(:coupon2) { create(:coupon, organization:) }

      before { coupon2 }

      it 'returns coupons with correct meta data' do
        get_with_token(organization, '/api/v1/coupons?page=1&per_page=1')

        expect(response).to have_http_status(:success)
        expect(json[:coupons].count).to eq(1)
        expect(json[:meta][:current_page]).to eq(1)
        expect(json[:meta][:next_page]).to eq(2)
        expect(json[:meta][:prev_page]).to eq(nil)
        expect(json[:meta][:total_pages]).to eq(2)
        expect(json[:meta][:total_count]).to eq(2)
      end
    end
  end
end
