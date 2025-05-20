# frozen_string_literal: true

FactoryBot.define do
  factory :applied_coupon do
    customer
    organization { customer.organization }
    coupon { association(:coupon, organization:) }

    amount_cents { 200 }
    amount_currency { "EUR" }
    status { "active" }
    frequency { "once" }
  end
end
