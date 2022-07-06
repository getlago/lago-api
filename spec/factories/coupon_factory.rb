FactoryBot.define do
  factory :coupon do
    organization
    name { Faker::Name.name }
    code { Faker::Name.first_name }
    status { 'active' }
    expiration { 'no_expiration' }
    amount_cents { 200 }
    amount_currency { 'EUR' }
  end
end
