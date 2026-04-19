# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::Quotes::BillingItems::CouponsController, :premium do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:coupon) { create(:coupon, organization:) }
  let(:quote) { create(:quote, organization:, customer:, order_type: :subscription_creation) }

  describe "POST /api/v1/quotes/:quote_id/coupons" do
    subject do
      post_with_token(organization, "/api/v1/quotes/#{quote.id}/coupons", {coupon: create_params})
    end

    let(:create_params) { {coupon_id: coupon.id, coupon_type: "fixed_amount", amount_cents: 5000, position: 1} }

    it "adds a coupon and returns the updated quote" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:quote][:billing_items]["coupons"].length).to eq(1)
      expect(json[:quote][:billing_items]["coupons"].first["coupon_id"]).to eq(coupon.id)
      expect(json[:quote][:billing_items]["coupons"].first["id"]).to start_with("qtc_")
    end

    context "when quote does not belong to organization" do
      it "returns not_found_error" do
        post_with_token(organization, "/api/v1/quotes/#{create(:quote).id}/coupons", {coupon: create_params})
        expect(response).to be_not_found_error("quote")
      end
    end

    context "when order type is one_off" do
      let(:quote) { create(:quote, organization:, customer:, order_type: :one_off) }

      it "returns unprocessable_entity" do
        subject
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "when quote is not draft" do
      before { quote.update!(status: :approved, approved_at: Time.current) }

      it "returns method_not_allowed" do
        subject
        expect(response).to have_http_status(:method_not_allowed)
      end
    end
  end

  describe "PUT /api/v1/quotes/:quote_id/coupons/:id" do
    subject do
      put_with_token(organization, "/api/v1/quotes/#{quote.id}/coupons/#{item_id}", {coupon: update_params})
    end

    let(:item_id) { "qtc_existing" }
    let(:update_params) { {amount_cents: 10_000} }

    before do
      quote.update!(billing_items: {
        "coupons" => [{"id" => item_id, "coupon_id" => coupon.id, "coupon_type" => "fixed_amount", "amount_cents" => 5000}]
      })
    end

    it "updates the coupon and returns the quote" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:quote][:billing_items]["coupons"].first["amount_cents"]).to eq(10_000)
    end

    context "when item id is not found" do
      it "returns not_found_error" do
        put_with_token(organization, "/api/v1/quotes/#{quote.id}/coupons/qtc_nonexistent", {coupon: update_params})
        expect(response).to be_not_found_error("billing_item")
      end
    end

    context "when quote is not draft" do
      before { quote.update!(status: :approved, approved_at: Time.current) }

      it "returns method_not_allowed" do
        subject
        expect(response).to have_http_status(:method_not_allowed)
      end
    end
  end

  describe "DELETE /api/v1/quotes/:quote_id/coupons/:id" do
    subject do
      delete_with_token(organization, "/api/v1/quotes/#{quote.id}/coupons/#{item_id}")
    end

    let(:item_id) { "qtc_to_remove" }

    before do
      quote.update!(billing_items: {
        "coupons" => [{"id" => item_id, "coupon_id" => coupon.id, "coupon_type" => "fixed_amount"}]
      })
    end

    it "removes the coupon and returns the updated quote" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:quote][:billing_items]["coupons"]).to be_empty
    end

    context "when item id is not found" do
      it "returns not_found_error" do
        delete_with_token(organization, "/api/v1/quotes/#{quote.id}/coupons/qtc_nonexistent")
        expect(response).to be_not_found_error("billing_item")
      end
    end

    context "when quote is not draft" do
      before { quote.update!(status: :approved, approved_at: Time.current) }

      it "returns method_not_allowed" do
        subject
        expect(response).to have_http_status(:method_not_allowed)
      end
    end
  end
end
