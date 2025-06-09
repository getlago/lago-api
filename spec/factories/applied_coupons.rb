# frozen_string_literal: true

FactoryBot.define do
  factory :applied_coupon do
    customer
    coupon
    organization { customer&.organization || coupon&.organization || association(:organization) }

    amount_cents { 200 }
    amount_currency { "EUR" }
    status { "active" }
    frequency { "once" }
  end
end
