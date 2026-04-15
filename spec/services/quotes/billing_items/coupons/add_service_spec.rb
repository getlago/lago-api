# frozen_string_literal: true

require "rails_helper"

RSpec.describe Quotes::BillingItems::Coupons::AddService do
  subject(:service) { described_class.new(quote:, params:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:coupon) { create(:coupon, organization:) }
  let(:quote) { create(:quote, organization:, customer:, order_type: :subscription_creation) }

  describe "#call" do
    let(:result) { service.call }

    context "with valid params" do
      let(:params) { {coupon_id: coupon.id, coupon_type: "fixed_amount", amount_cents: 5000, position: 1} }

      it "appends the coupon and returns the quote" do
        expect(result).to be_success
        expect(result.quote.billing_items["coupons"].length).to eq(1)
        expect(result.quote.billing_items["coupons"].first["coupon_id"]).to eq(coupon.id)
      end

      it "generates a stable id with qtc_ prefix" do
        expect(result.quote.billing_items["coupons"].first["id"]).to start_with("qtc_")
      end
    end

    context "with percentage coupon type" do
      let(:params) { {coupon_id: coupon.id, coupon_type: "percentage", percentage_rate: "20.0", position: 1} }

      it "returns success" do
        expect(result).to be_success
      end
    end

    context "when quote is not draft" do
      let(:params) { {coupon_id: coupon.id, coupon_type: "fixed_amount"} }

      before { quote.update!(status: :approved, approved_at: Time.current) }

      it "returns not_allowed_failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
      end
    end

    context "when order type is one_off" do
      let(:quote) { create(:quote, organization:, customer:, order_type: :one_off) }
      let(:params) { {coupon_id: coupon.id, coupon_type: "fixed_amount"} }

      it "returns validation_failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:billing_item]).to include("coupons not allowed for one_off order type")
      end
    end

    context "when coupon_id is missing" do
      let(:params) { {coupon_type: "fixed_amount"} }

      it "returns validation_failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:billing_item]).to include("coupon_id is required")
      end
    end

    context "when coupon does not belong to organization" do
      let(:other_coupon) { create(:coupon) }
      let(:params) { {coupon_id: other_coupon.id, coupon_type: "fixed_amount"} }

      it "returns validation_failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:billing_item]).to include("coupon not found in organization")
      end
    end

    context "when coupon_type is invalid" do
      let(:params) { {coupon_id: coupon.id, coupon_type: "unknown"} }

      it "returns validation_failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:billing_item]).to include("coupon_type is invalid")
      end
    end
  end
end
