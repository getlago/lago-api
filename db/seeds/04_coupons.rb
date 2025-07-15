# frozen_string_literal: true

organization = Organization.find_by!(name: "Hooli")

# Percentage coupon
Coupons::CreateService.call!(
  organization_id: organization.id,
  name: "20% off",
  code: "20_percent_off",
  coupon_type: "percentage",
  percentage_rate: 20,
  frequency: "forever",
  expiration: "no_expiration"
)

# Fixed amount coupon
Coupons::CreateService.call!(
  organization_id: organization.id,
  name: "10€ off",
  code: "10_euro_off",
  coupon_type: "fixed_amount",
  amount_cents: 1000,
  amount_currency: "EUR",
  frequency: "forever",
  expiration: "no_expiration"
)
