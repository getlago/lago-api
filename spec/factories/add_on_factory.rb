FactoryBot.define do
  factory :add_on do
    organization
    name { Faker::Name.name }
    code { Faker::Name.first_name }
    description { 'test description' }
    amount_cents { 200 }
    amount_currency { 'EUR' }
  end
end
