# frozen_string_literal: true

FactoryBot.define do
  factory :wallet do
    customer
    name { Faker::Name.name }
    status { 'active' }
    rate_amount { '1.00' }
    currency { 'EUR' }
    credits_balance { '0.00' }
    balance { '0.00' }
    consumed_credits { '0.00' }
  end
end
