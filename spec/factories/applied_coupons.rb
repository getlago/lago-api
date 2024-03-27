# frozen_string_literal: true

FactoryBot.define do
  factory :applied_coupon do
    customer
    coupon

    amount_cents { 200 }
    amount_currency { "EUR" }
    status { "active" }
    frequency { "once" }
  end
end
