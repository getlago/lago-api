# frozen_string_literal: true

FactoryBot.define do
  factory :customer do
    organization
    name { Faker::TvShows::SiliconValley.character }
    external_id { SecureRandom.uuid }
    country { Faker::Address.country_code }
    address_line1 { Faker::Address.street_address }
    address_line2 { Faker::Address.secondary_address }
    state { Faker::Address.state }
    zipcode { Faker::Address.zip_code }
    email { Faker::Internet.email }
    city { Faker::Address.city }
    url { Faker::Internet.url }
    phone { Faker::PhoneNumber.phone_number }
    logo_url { Faker::Internet.url }
    legal_name { Faker::Company.name }
    legal_number { Faker::Company.duns_number }
    currency { 'EUR' }
  end
end
