# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::CouponsController, type: :request do
  let(:organization) { create(:organization) }

  describe 'create' do
    let(:create_params) do
      {
        name: 'coupon1',
        code: 'coupon1_code',
        amount_cents: 123,
        amount_currency: 'EUR',
        expiration: 'time_limit',
        expiration_duration: 15
      }
    end

    it 'creates a coupon' do
      post_with_token(organization, '/api/v1/coupons', { coupon: create_params })

      expect(response).to have_http_status(:success)

      result = JSON.parse(response.body, symbolize_names: true)[:coupon]
      expect(result[:lago_id]).to be_present
      expect(result[:code]).to eq(create_params[:code])
      expect(result[:name]).to eq(create_params[:name])
      expect(result[:created_at]).to be_present
    end
  end

  describe 'update' do
    let(:coupon) { create(:coupon, organization: organization) }
    let(:code) { 'coupon_code' }
    let(:update_params) do
      {
        name: 'coupon1',
        code: code,
        amount_cents: 123,
        amount_currency: 'EUR',
        expiration: 'time_limit',
        expiration_duration: 15
      }
    end

    it 'updates a coupon' do
      put_with_token(organization,
                     "/api/v1/coupons/#{coupon.code}",
                     { coupon: update_params }
      )

      expect(response).to have_http_status(:success)

      result = JSON.parse(response.body, symbolize_names: true)[:coupon]

      expect(result[:lago_id]).to eq(coupon.id)
      expect(result[:code]).to eq(update_params[:code])
    end

    context 'when coupon does not exist' do
      it 'returns not_found error' do
        put_with_token(organization, '/api/v1/coupons/invalid', { coupon: update_params })

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when coupon code already exists in organization scope (validation error)' do
      let(:coupon2) { create(:coupon, organization: organization) }
      let(:code) { coupon2.code }

      before { coupon2 }

      it 'returns unprocessable_entity error' do
        put_with_token(organization,
                       "/api/v1/coupons/#{coupon.code}",
                       { coupon: update_params }
        )

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'show' do
    let(:coupon) { create(:coupon, organization: organization) }

    it 'returns a coupon' do
      get_with_token(
        organization,
        "/api/v1/coupons/#{coupon.code}"
      )

      expect(response).to have_http_status(:success)

      result = JSON.parse(response.body, symbolize_names: true)[:coupon]

      expect(result[:lago_id]).to eq(coupon.id)
      expect(result[:code]).to eq(coupon.code)
    end

    context 'when coupon does not exist' do
      it 'returns not found' do
        get_with_token(
          organization,
          "/api/v1/coupons/555"
        )

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'destroy' do
    let(:coupon) { create(:coupon, organization: organization) }

    before { coupon }

    it 'deletes a coupon' do
      expect { delete_with_token(organization, "/api/v1/coupons/#{coupon.code}") }
        .to change(Coupon, :count).by(-1)
    end

    it 'returns deleted coupon' do
      delete_with_token(organization, "/api/v1/coupons/#{coupon.code}")

      expect(response).to have_http_status(:success)

      result = JSON.parse(response.body, symbolize_names: true)[:coupon]

      expect(result[:lago_id]).to eq(coupon.id)
      expect(result[:code]).to eq(coupon.code)
    end

    context 'when coupon does not exist' do
      it 'returns not_found error' do
        delete_with_token(organization, '/api/v1/coupons/invalid')

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when coupon is attached to customer' do
      let(:applied_coupon) { create(:applied_coupon, coupon: coupon) }

      before { applied_coupon }

      it 'returns forbidden error' do
        delete_with_token(organization, "/api/v1/coupons/#{coupon.code}")

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'index' do
    let(:coupon) { create(:coupon, organization: organization) }

    before { coupon }

    it 'returns coupons' do
      get_with_token(organization, '/api/v1/coupons')

      expect(response).to have_http_status(:success)

      records = JSON.parse(response.body, symbolize_names: true)[:coupons]

      expect(records.count).to eq(1)
      expect(records.first[:lago_id]).to eq(coupon.id)
      expect(records.first[:code]).to eq(coupon.code)
    end

    context 'with pagination' do
      let(:coupon2) { create(:coupon, organization: organization) }

      before { coupon2 }

      it 'returns coupons with correct meta data' do
        get_with_token(organization, '/api/v1/coupons?page=1&per_page=1')

        expect(response).to have_http_status(:success)

        response_body = JSON.parse(response.body, symbolize_names: true)

        expect(response_body[:coupons].count).to eq(1)
        expect(response_body[:meta][:current_page]).to eq(1)
        expect(response_body[:meta][:next_page]).to eq(2)
        expect(response_body[:meta][:prev_page]).to eq(nil)
        expect(response_body[:meta][:total_pages]).to eq(2)
        expect(response_body[:meta][:total_count]).to eq(2)
      end
    end
  end
end
