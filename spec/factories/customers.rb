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

    trait :with_shipping_address do
      shipping_address_line1 { Faker::Address.street_address }
      shipping_address_line2 { Faker::Address.secondary_address }
      shipping_city { Faker::Address.city }
      shipping_zipcode { Faker::Address.zip_code }
      shipping_state { Faker::Address.state }
      shipping_country { Faker::Address.country_code }
    end

    trait :with_same_billing_and_shipping_address do
      shipping_address_line1 { address_line1 }
      shipping_address_line2 { address_line2 }
      shipping_city { city }
      shipping_zipcode { zipcode }
      shipping_state { state }
      shipping_country { country }
    end
  end
end
