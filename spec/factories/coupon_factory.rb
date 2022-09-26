FactoryBot.define do
  factory :coupon do
    organization
    name { Faker::Name.name }
    code { Faker::Name.first_name }
    coupon_type { 'fixed_amount' }
    status { 'active' }
    expiration { 'no_expiration' }
    amount_cents { 200 }
    amount_currency { 'EUR' }
    frequency { 'once' }
  end
end
