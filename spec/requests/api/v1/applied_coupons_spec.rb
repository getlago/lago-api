# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::AppliedCouponsController, type: :request do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization: organization) }
  let(:coupon) { create(:coupon, organization: organization) }

  describe 'apply' do
    before do
      create(:active_subscription, customer: customer)
    end

    let(:params) do
      {
        external_customer_id: customer.external_id,
        coupon_code: coupon.code,
      }
    end

    it 'returns a success' do
      post_with_token(
        organization,
        '/api/v1/applied_coupons',
        { applied_coupon: params },
      )

      expect(response).to have_http_status(:success)

      result = JSON.parse(response.body, symbolize_names: true)[:applied_coupon]

      aggregate_failures do
        expect(result[:lago_id]).to be_present
        expect(result[:lago_coupon_id]).to eq(coupon.id)
        expect(result[:lago_customer_id]).to eq(customer.id)
        expect(result[:external_customer_id]).to eq(customer.external_id)
        expect(result[:amount_cents]).to eq(coupon.amount_cents)
        expect(result[:amount_currency]).to eq(coupon.amount_currency)
        expect(result[:expiration_date]).to be_nil
        expect(result[:created_at]).to be_present
        expect(result[:terminated_at]).to be_nil
      end
    end

    context 'with invalid params' do
      let(:params) do
        {
          name: 'Foo Bar',
        }
      end

      it 'returns an unprocessable_entity' do
        post_with_token(organization, '/api/v1/applied_coupons', { applied_coupon: params })

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
