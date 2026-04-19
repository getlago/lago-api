# frozen_string_literal: true

require "rails_helper"

RSpec.describe Quotes::BillingItems::Coupons::RemoveService, :premium do
  subject(:service) { described_class.new(quote:, id:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:coupon) { create(:coupon, organization:) }
  let(:item_id) { "qtc_to_remove" }
  let(:quote) do
    create(:quote, organization:, customer:, order_type: :subscription_creation,
      billing_items: {"coupons" => [{"id" => item_id, "coupon_id" => coupon.id, "coupon_type" => "fixed_amount"}]})
  end

  describe "#call" do
    let(:result) { service.call }

    context "when item exists" do
      let(:id) { item_id }

      it "removes the coupon from billing_items and returns the quote" do
        expect(result).to be_success
        expect(result.quote.billing_items["coupons"]).to be_empty
      end

      it "only removes the targeted item when multiple coupons exist" do
        other_item = {"id" => "qtc_other", "coupon_id" => create(:coupon, organization:).id, "coupon_type" => "percentage"}
        quote.update!(billing_items: {
          "coupons" => [
            {"id" => item_id, "coupon_id" => coupon.id, "coupon_type" => "fixed_amount"},
            other_item
          ]
        })

        expect(result.quote.billing_items["coupons"].map { |c| c["id"] }).to eq(["qtc_other"])
      end
    end

    context "when quote is nil" do
      let(:id) { item_id }

      it "returns not_found_failure" do
        result = described_class.new(quote: nil, id:).call
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("quote")
      end
    end

    context "when quote is not draft" do
      let(:id) { item_id }

      before { quote.update!(status: :approved, approved_at: Time.current) }

      it "returns not_allowed_failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
      end
    end

    context "when item id is not found" do
      let(:id) { "qtc_nonexistent" }

      it "returns not_found_failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("billing_item")
      end
    end
  end
end
