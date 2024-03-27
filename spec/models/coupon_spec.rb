# frozen_string_literal: true

require "rails_helper"

RSpec.describe Coupon, type: :model do
  subject(:coupon) { create(:coupon) }

  let(:organization) { create(:organization) }

  it_behaves_like "paper_trail traceable"

  describe "validations" do
    context "when coupon is fixed amount" do
      it "validates amount_cents" do
        expect(coupon).to be_valid

        coupon.amount_cents = nil
        expect(coupon).not_to be_valid
      end

      it "validates amount_currency" do
        coupon.amount_currency = nil
        expect(coupon).not_to be_valid
      end

      it "validates percentage_rate" do
        coupon.percentage_rate = nil
        expect(coupon).to be_valid
      end
    end

    context "when coupon is percentage" do
      subject(:coupon) { create(:coupon, coupon_type: "percentage", percentage_rate: 10) }

      it "validates percentage_rate" do
        expect(coupon).to be_valid

        coupon.percentage_rate = nil
        expect(coupon).not_to be_valid
      end

      it "validates amount_cents" do
        coupon.amount_cents = nil
        expect(coupon).to be_valid
      end

      it "validates amount_currency" do
        coupon.amount_currency = nil
        expect(coupon).to be_valid
      end
    end
  end

  describe ".mark_as_terminated" do
    it "terminates the coupon" do
      coupon.mark_as_terminated!

      aggregate_failures do
        expect(coupon).to be_terminated
        expect(coupon.terminated_at).to be_present
      end
    end
  end
end
