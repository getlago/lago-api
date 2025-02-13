# frozen_string_literal: true

FactoryBot.define do
  factory :wallet do
    customer
    name { Faker::Name.name }
    status { "active" }
    rate_amount { "1.00" }
    currency { "EUR" }
    credits_balance { 0 }
    balance_cents { 0 }
    consumed_credits { 0 }

    trait :terminated do
      status { "terminated" }
    end
  end
end
