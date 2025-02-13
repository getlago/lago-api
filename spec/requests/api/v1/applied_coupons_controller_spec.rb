# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::AppliedCouponsController, type: :request do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:coupon) { create(:coupon, organization:) }

  describe "POST /api/v1/applied_coupons" do
    subject do
      post_with_token(organization, "/api/v1/applied_coupons", {applied_coupon: params})
    end

    let(:params) do
      {
        external_customer_id: customer.external_id,
        coupon_code: coupon.code
      }
    end

    before { create(:subscription, customer:) }

    include_examples "requires API permission", "applied_coupon", "write"

    it "returns a success" do
      subject

      expect(response).to have_http_status(:success)

      aggregate_failures do
        expect(json[:applied_coupon][:lago_id]).to be_present
        expect(json[:applied_coupon][:lago_coupon_id]).to eq(coupon.id)
        expect(json[:applied_coupon][:lago_customer_id]).to eq(customer.id)
        expect(json[:applied_coupon][:external_customer_id]).to eq(customer.external_id)
        expect(json[:applied_coupon][:amount_cents]).to eq(coupon.amount_cents)
        expect(json[:applied_coupon][:amount_currency]).to eq(coupon.amount_currency)
        expect(json[:applied_coupon][:expiration_at]).to be_nil
        expect(json[:applied_coupon][:created_at]).to be_present
        expect(json[:applied_coupon][:terminated_at]).to be_nil
      end
    end

    context "with invalid params" do
      let(:params) do
        {name: "Foo Bar"}
      end

      it "returns an unprocessable_entity" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "GET /api/v1/applied_coupons" do
    subject { get_with_token(organization, "/api/v1/applied_coupons") }

    let(:coupon) { create(:coupon, coupon_type: "fixed_amount", organization:) }

    let(:applied_coupon) do
      create(
        :applied_coupon,
        customer:,
        coupon:,
        amount_cents: 10,
        amount_currency: customer.currency
      )
    end

    before do
      create(:credit, applied_coupon:, amount_cents: 2, amount_currency: customer.currency)
    end

    include_examples "requires API permission", "applied_coupon", "read"

    it "returns applied coupons" do
      subject

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(json[:applied_coupons].count).to eq(1)
        expect(json[:applied_coupons].first[:lago_id]).to eq(applied_coupon.id)
        expect(json[:applied_coupons].first[:amount_cents]).to eq(applied_coupon.amount_cents)
        expect(json[:applied_coupons].first[:amount_cents_remaining]).to eq(8)

        expect(json[:meta][:current_page]).to eq(1)
        expect(json[:meta][:next_page]).to eq(nil)
        expect(json[:meta][:prev_page]).to eq(nil)
        expect(json[:meta][:total_pages]).to eq(1)
        expect(json[:meta][:total_count]).to eq(1)
      end
    end
  end
end
