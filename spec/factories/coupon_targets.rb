# frozen_string_literal: true

FactoryBot.define do
  factory :coupon_plan, class: "CouponTarget" do
    coupon
    plan
  end

  factory :coupon_billable_metric, class: "CouponTarget" do
    coupon
    billable_metric
  end
end
