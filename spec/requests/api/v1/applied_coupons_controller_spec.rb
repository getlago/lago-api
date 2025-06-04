# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::AppliedCouponsController, type: :request do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }

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

    let(:coupon) { create(:coupon, organization:) }

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
    subject { get_with_token(organization, "/api/v1/applied_coupons", params) }

    let(:params) { {} }

    let(:customer_2) { create(:customer, organization:) }

    let(:coupon_1) { create(:coupon, coupon_type: "fixed_amount", organization:) }
    let(:coupon_2) { create(:coupon, coupon_type: "fixed_amount", organization:) }

    let!(:applied_coupon_1) do
      create(
        :applied_coupon,
        customer:,
        coupon: coupon_1,
        amount_cents: 10,
        amount_currency: customer.currency
      )
    end
    let!(:applied_coupon_2) do
      create(
        :applied_coupon,
        customer: customer_2,
        coupon: coupon_2,
        amount_cents: 10,
        amount_currency: customer.currency
      )
    end

    before do
      create(:credit, applied_coupon: applied_coupon_1, amount_cents: 2, amount_currency: customer.currency)
    end

    include_examples "requires API permission", "applied_coupon", "read"

    it "returns applied coupons" do
      subject

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(json[:applied_coupons].count).to eq(2)
        expect(json[:applied_coupons].first[:lago_id]).to eq(applied_coupon_2.id)
        expect(json[:applied_coupons].last[:lago_id]).to eq(applied_coupon_1.id)
        expect(json[:applied_coupons].last[:amount_cents]).to eq(applied_coupon_1.amount_cents)
        expect(json[:applied_coupons].last[:amount_cents_remaining]).to eq(8)

        expect(json[:meta][:current_page]).to eq(1)
        expect(json[:meta][:next_page]).to eq(nil)
        expect(json[:meta][:prev_page]).to eq(nil)
        expect(json[:meta][:total_pages]).to eq(1)
        expect(json[:meta][:total_count]).to eq(2)
      end
    end

    context "with pagination" do
      let(:params) { {page: 2, per_page: 1} }

      it "returns paginated applied coupons" do
        subject

        aggregate_failures do
          expect(response).to have_http_status(:success)
          expect(json[:applied_coupons].count).to eq(1)
          expect(json[:applied_coupons].first[:lago_id]).to eq(applied_coupon_1.id)

          expect(json[:meta][:current_page]).to eq(2)
          expect(json[:meta][:next_page]).to eq(nil)
          expect(json[:meta][:prev_page]).to eq(1)
          expect(json[:meta][:total_pages]).to eq(2)
          expect(json[:meta][:total_count]).to eq(2)
        end
      end
    end

    context "with external_customer_id filter" do
      let(:params) { {external_customer_id: customer.external_id} }

      it "returns only the applied coupons for the specified customer" do
        subject

        aggregate_failures do
          expect(response).to have_http_status(:success)
          expect(json[:applied_coupons].count).to eq(1)
          expect(json[:applied_coupons].first[:lago_id]).to eq(applied_coupon_1.id)
        end
      end

      context "when no applied coupons match the external_customer_id" do
        let(:params) { {external_customer_id: "non_existent_id"} }

        it "returns an empty array" do
          subject

          aggregate_failures do
            expect(response).to have_http_status(:success)
            expect(json[:applied_coupons]).to be_empty
          end
        end
      end
    end

    context "with status filter" do
      let(:params) { {status: "active"} }

      it "returns only the applied coupons with the specified status" do
        subject

        aggregate_failures do
          expect(response).to have_http_status(:success)
          expect(json[:applied_coupons].count).to eq(2)
          expect(json[:applied_coupons].first[:lago_id]).to eq(applied_coupon_2.id)
          expect(json[:applied_coupons].last[:lago_id]).to eq(applied_coupon_1.id)
        end
      end

      context "when no applied coupons match the status" do
        let(:params) { {status: "terminated"} }

        it "returns an empty array" do
          subject

          aggregate_failures do
            expect(response).to have_http_status(:success)
            expect(json[:applied_coupons]).to be_empty
          end
        end
      end
    end

    context "with coupon_code filter" do
      context "when coupon_code fitlering is an array" do
        let(:params) { {coupon_code: [coupon_1.code]} }

        it "returns only the applied coupons for the specified coupon code" do
          subject

          aggregate_failures do
            expect(response).to have_http_status(:success)
            expect(json[:applied_coupons].count).to eq(1)
            expect(json[:applied_coupons].first[:lago_id]).to eq(applied_coupon_1.id)
          end
        end
      end

      context "when no applied coupons match the coupon code" do
        let(:params) { {coupon_code: "non_existent_code"} }

        it "returns an empty array" do
          subject

          aggregate_failures do
            expect(response).to have_http_status(:success)
            expect(json[:applied_coupons]).to be_empty
          end
        end
      end
    end
  end
end
