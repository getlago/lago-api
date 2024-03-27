# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::Customers::AppliedCouponsController, type: :request do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }

  describe "destroy" do
    let(:applied_coupon) { create(:applied_coupon, customer:) }
    let(:identifier) { applied_coupon.id }

    before { applied_coupon }

    it "terminates the applied coupon" do
      expect do
        delete_with_token(organization, "/api/v1/customers/#{customer.external_id}/applied_coupons/#{identifier}")
      end.to change { applied_coupon.reload.status }.from("active").to("terminated")
    end

    it "returns the applied_coupon" do
      delete_with_token(organization, "/api/v1/customers/#{customer.external_id}/applied_coupons/#{identifier}")

      expect(response).to have_http_status(:success)
      expect(json[:applied_coupon][:lago_id]).to eq(applied_coupon.id)
    end

    context "when customer does not exist" do
      it "returns not_found error" do
        delete_with_token(organization, "/api/v1/customers/unknown/applied_coupons/#{identifier}")

        expect(response).to have_http_status(:not_found)
      end
    end

    context "when applied coupon does not exist" do
      let(:identifier) { "unknown" }

      it "returns not_found error" do
        delete_with_token(organization, "/api/v1/customers/#{customer.external_id}/applied_coupons/#{identifier}")

        expect(response).to have_http_status(:not_found)
      end
    end

    context "when coupon is not applied to customer" do
      let(:other_applied_coupon) { create(:applied_coupon) }
      let(:identifier) { other_applied_coupon.id }

      it "returns not_found error" do
        delete_with_token(organization, "/api/v1/customers/#{customer.external_id}/applied_coupons/#{identifier}")

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
