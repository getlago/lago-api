# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::Customers::AppliedCouponsController, type: :request do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }

  let(:external_id) { customer.external_id }

  describe "GET /api/v1/customers/:external_id/applied_coupons" do
    subject { get_with_token(organization, "/api/v1/customers/#{external_id}/applied_coupons", params) }

    let(:params) { {} }

    let(:coupon) { create(:coupon, coupon_type: "fixed_amount", organization:) }

    let!(:applied_coupon) do
      create(
        :applied_coupon,
        customer:,
        coupon: coupon,
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

      expect(response).to have_http_status(:success)
      expect(json[:applied_coupons].count).to eq(1)

      applied_result = json[:applied_coupons].first
      expect(applied_result[:lago_id]).to eq(applied_coupon.id)
      expect(applied_result[:amount_cents]).to eq(applied_coupon.amount_cents)
      expect(applied_result[:amount_cents_remaining]).to eq(8)

      expect(json[:meta][:current_page]).to eq(1)
      expect(json[:meta][:next_page]).to eq(nil)
      expect(json[:meta][:prev_page]).to eq(nil)
      expect(json[:meta][:total_pages]).to eq(1)
      expect(json[:meta][:total_count]).to eq(1)
    end

    context "with pagination" do
      let(:params) { {page: 2, per_page: 1} }

      it "returns paginated applied coupons" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:applied_coupons]).to be_empty
      end
    end

    context "with status filter" do
      let(:params) { {status: "active"} }

      it "returns only the applied coupons with the specified status" do
        subject

        applied_result = json[:applied_coupons].first
        expect(applied_result[:lago_id]).to eq(applied_coupon.id)
        expect(applied_result[:amount_cents]).to eq(applied_coupon.amount_cents)
        expect(applied_result[:amount_cents_remaining]).to eq(8)
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
        let(:params) { {coupon_code: [coupon.code]} }

        it "returns only the applied coupons for the specified coupon code" do
          subject

          aggregate_failures do
            expect(response).to have_http_status(:success)
            expect(json[:applied_coupons].count).to eq(1)
            expect(json[:applied_coupons].first[:lago_id]).to eq(applied_coupon.id)
          end
        end

        context "when the coupon is deleted" do
          let(:coupon) { create(:coupon, :deleted, organization:) }
          let!(:applied_coupon) do
            create(
              :applied_coupon,
              :terminated,
              customer:,
              coupon: coupon,
              amount_cents: 10,
              amount_currency: customer.currency
            )
          end

          it "returns the applied coupon" do
            subject

            expect(response).to have_http_status(:success)
            expect(json[:applied_coupons].count).to eq(1)
            expect(json[:applied_coupons].first[:lago_id]).to eq(applied_coupon.id)
          end
        end
      end

      context "when no applied coupons match the coupon code" do
        let(:params) { {coupon_code: ["non_existent_code"]} }

        it "returns an empty array" do
          subject

          aggregate_failures do
            expect(response).to have_http_status(:success)
            expect(json[:applied_coupons]).to be_empty
          end
        end
      end
    end

    context "when the coupon is deleted" do
      let(:coupon) { create(:coupon, :deleted, organization:) }
      let!(:applied_coupon) do
        create(
          :applied_coupon,
          :terminated,
          customer:,
          coupon: coupon,
          amount_cents: 10,
          amount_currency: customer.currency
        )
      end

      it "returns the applied coupon" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:applied_coupons].count).to eq(1)
        expect(json[:applied_coupons].last[:lago_id]).to eq(applied_coupon.id)
        expect(json[:applied_coupons].last[:coupon_code]).to eq(coupon.code)
        expect(json[:applied_coupons].last[:coupon_name]).to eq(coupon.name)
      end
    end

    context "when customer external_id is unknown" do
      let(:external_id) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to have_http_status(:not_found)
      end
    end

    context "when customer belongs to another organization" do
      let(:customer) { create(:customer) }

      it "returns a not found error" do
        subject

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "DELETE /api/v1/customers/:customer_external_id/applied_coupons/:id" do
    subject do
      delete_with_token(
        organization,
        "/api/v1/customers/#{external_id}/applied_coupons/#{identifier}"
      )
    end

    let!(:applied_coupon) { create(:applied_coupon, customer:) }
    let(:external_id) { customer.external_id }
    let(:identifier) { applied_coupon.id }

    include_examples "requires API permission", "applied_coupon", "write"

    it "terminates the applied coupon" do
      expect { subject }
        .to change { applied_coupon.reload.status }.from("active").to("terminated")
    end

    it "returns the applied_coupon" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:applied_coupon][:lago_id]).to eq(applied_coupon.id)
    end

    context "when customer does not exist" do
      let(:external_id) { SecureRandom.uuid }

      it "returns not_found error" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when applied coupon does not exist" do
      let(:identifier) { SecureRandom.uuid }

      it "returns not_found error" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when coupon is not applied to customer" do
      let(:other_applied_coupon) { create(:applied_coupon) }
      let(:identifier) { other_applied_coupon.id }

      it "returns not_found error" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
