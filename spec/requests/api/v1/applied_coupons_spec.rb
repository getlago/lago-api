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

      aggregate_failures do
        expect(json[:applied_coupon][:lago_id]).to be_present
        expect(json[:applied_coupon][:lago_coupon_id]).to eq(coupon.id)
        expect(json[:applied_coupon][:lago_customer_id]).to eq(customer.id)
        expect(json[:applied_coupon][:external_customer_id]).to eq(customer.external_id)
        expect(json[:applied_coupon][:amount_cents]).to eq(coupon.amount_cents)
        expect(json[:applied_coupon][:amount_currency]).to eq(coupon.amount_currency)
        expect(json[:applied_coupon][:expiration_date]).to be_nil
        expect(json[:applied_coupon][:created_at]).to be_present
        expect(json[:applied_coupon][:terminated_at]).to be_nil
      end
    end

    context 'with invalid params' do
      let(:params) do
        { name: 'Foo Bar' }
      end

      it 'returns an unprocessable_entity' do
        post_with_token(organization, '/api/v1/applied_coupons', { applied_coupon: params })

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'index' do
    let(:customer) { create(:customer, organization: organization) }
    let(:coupon) { create(:coupon, coupon_type: 'fixed_amount', organization: organization) }
    let(:credit) do
      create(:credit, applied_coupon: applied_coupon, amount_cents: 2, amount_currency: customer.currency)
    end
    let(:applied_coupon) do
      create(
        :applied_coupon,
        customer: customer,
        coupon: coupon,
        amount_cents: 10,
        amount_currency: customer.currency,
      )
    end

    before do
      applied_coupon
      credit
    end

    it 'returns applied coupons' do
      get_with_token(organization, '/api/v1/applied_coupons')

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(json[:applied_coupons].count).to eq(1)
        expect(json[:applied_coupons].first[:lago_id]).to eq(applied_coupon.id)
        expect(json[:applied_coupons].first[:amount_cents]).to eq(applied_coupon.amount_cents)
        expect(json[:applied_coupons].first[:amount_cents_remaining]).to eq(8)
      end
    end

    context 'with pagination' do
      let(:coupon_latest) { create(:coupon, coupon_type: 'percentage', organization: organization) }
      let(:applied_coupon_latest) do
        create(
          :applied_coupon,
          coupon: coupon_latest,
          customer: customer,
          percentage_rate: 20.00,
          created_at: applied_coupon.created_at + 1.day,
        )
      end

      before { applied_coupon_latest }

      it 'returns applied coupons with correct meta data' do
        get_with_token(organization, '/api/v1/applied_coupons?page=1&per_page=1')

        aggregate_failures do
          expect(response).to have_http_status(:success)
          expect(json[:applied_coupons].count).to eq(1)
          expect(json[:meta][:current_page]).to eq(1)
          expect(json[:meta][:next_page]).to eq(2)
          expect(json[:meta][:prev_page]).to eq(nil)
          expect(json[:meta][:total_pages]).to eq(2)
          expect(json[:meta][:total_count]).to eq(2)
        end
      end
    end

    context 'with status param' do
      let(:coupon_latest) { create(:coupon, coupon_type: 'percentage', organization: organization) }
      let(:applied_coupon_latest) do
        create(
          :applied_coupon,
          coupon: coupon_latest,
          customer: customer,
          status: :terminated,
          percentage_rate: 20.00,
          created_at: applied_coupon.created_at + 1.day,
        )
      end

      before { applied_coupon_latest }

      it 'returns applied coupons with correct status' do
        get_with_token(organization, '/api/v1/applied_coupons?status=terminated')

        aggregate_failures do
          expect(response).to have_http_status(:success)
          expect(json[:applied_coupons].count).to eq(1)
          expect(json[:applied_coupons].first[:lago_id]).to eq(applied_coupon_latest.id)
        end
      end
    end

    context 'with external_customer_id params' do
      let(:customer_new) { create(:customer, organization: organization) }
      let(:coupon_latest) { create(:coupon, coupon_type: 'percentage', organization: organization) }
      let(:applied_coupon_latest) do
        create(
          :applied_coupon,
          coupon: coupon_latest,
          customer: customer_new,
          status: :active,
          percentage_rate: 20.00,
          created_at: applied_coupon.created_at + 1.day,
        )
      end

      before { applied_coupon_latest }

      it 'returns applied coupons of the selected customer' do
        get_with_token(organization, "/api/v1/applied_coupons?external_customer_id=#{customer_new.external_id}")

        aggregate_failures do
          expect(response).to have_http_status(:success)
          expect(json[:applied_coupons].count).to eq(1)
          expect(json[:applied_coupons].first[:lago_id]).to eq(applied_coupon_latest.id)
        end
      end
    end
  end
end
