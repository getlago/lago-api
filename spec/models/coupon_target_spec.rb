# frozen_string_literal: true

RSpec.describe CouponTarget do
  subject(:coupon_target) { build(:coupon_plan) }

  describe "associations" do
    it do
      expect(coupon_target).to belong_to(:coupon)
      expect(coupon_target).to belong_to(:organization)
      expect(coupon_target).to belong_to(:plan).optional
      expect(coupon_target).to belong_to(:catalog_plan).optional
      expect(coupon_target).to belong_to(:billable_metric).optional
    end
  end

  describe "validations" do
    describe "single_plan_target" do
      it "allows targeting only a catalog plan" do
        expect(build(:coupon_catalog_plan)).to be_valid
      end

      it "rejects targeting a legacy and a catalog plan at once" do
        target = build(:coupon_plan, catalog_plan: build(:catalog_plan))

        expect(target).not_to be_valid
        expect(target.errors.where(:base, :single_plan_target)).to be_present
      end
    end
  end
end
