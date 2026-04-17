# frozen_string_literal: true

require "rails_helper"

RSpec.describe Quotes::BillingItems::Coupons::UpdateService do
  subject(:service) { described_class.new(quote:, id:, params:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:coupon) { create(:coupon, organization:) }
  let(:item_id) { "qtc_existing" }
  let(:quote) do
    create(:quote, organization:, customer:, order_type: :subscription_creation,
      billing_items: {
        "coupons" => [{"id" => item_id, "coupon_id" => coupon.id, "coupon_type" => "fixed_amount", "amount_cents" => 5000}]
      })
  end

  describe "#call" do
    let(:result) { service.call }
    let(:id) { item_id }

    context "with valid params" do
      let(:params) { {amount_cents: 10_000} }

      it "updates the coupon fields and returns the quote" do
        expect(result).to be_success
        expect(result.quote.billing_items["coupons"].first["amount_cents"]).to eq(10_000)
      end

      it "preserves the existing id" do
        expect(result.quote.billing_items["coupons"].first["id"]).to eq(item_id)
      end
    end

    context "when quote is nil" do
      let(:id) { item_id }
      let(:params) { {amount_cents: 1000} }

      it "returns not_found_failure" do
        result = described_class.new(quote: nil, id:, params:).call
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("quote")
      end
    end

    context "when quote is not draft" do
      let(:params) { {amount_cents: 10_000} }

      before { quote.update!(status: :approved, approved_at: Time.current) }

      it "returns not_allowed_failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
      end
    end

    context "when item id is not found" do
      let(:id) { "qtc_nonexistent" }
      let(:params) { {amount_cents: 1000} }

      it "returns not_found_failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("billing_item")
      end
    end

    context "when coupon_type is updated to an invalid value" do
      let(:params) { {coupon_type: "unknown"} }

      it "returns validation_failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:billing_item]).to include("coupon_type is invalid")
      end
    end

    context "when coupon_id is updated to one from another organization" do
      let(:other_coupon) { create(:coupon) }
      let(:params) { {coupon_id: other_coupon.id} }

      it "returns validation_failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:billing_item]).to include("coupon not found in organization")
      end
    end
  end
end
