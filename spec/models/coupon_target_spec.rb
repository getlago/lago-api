# frozen_string_literal: true

RSpec.describe CouponTarget, type: :model do
  subject(:coupon_target) { build(:coupon_plan) }

  it { is_expected.to belong_to(:organization) }
end
