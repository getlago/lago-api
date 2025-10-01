# frozen_string_literal: true

FactoryBot.define do
  factory :customer_snapshot do
    invoice
    organization { invoice.organization }

    display_name { Faker::Name.name }
    firstname { Faker::Name.first_name }
    lastname { Faker::Name.last_name }
    email { Faker::Internet.email }
    phone { Faker::PhoneNumber.phone_number }
    url { Faker::Internet.url }
    tax_identification_number { Faker::Number.number(digits: 10).to_s }
    applicable_timezone { "UTC" }
    address_line1 { Faker::Address.street_address }
    address_line2 { Faker::Address.secondary_address }
    city { Faker::Address.city }
    state { Faker::Address.state }
    zipcode { Faker::Address.zip_code }
    country { Faker::Address.country_code }
    legal_name { Faker::Company.name }
    legal_number { Faker::Company.duns_number }
    shipping_address_line1 { Faker::Address.street_address }
    shipping_address_line2 { Faker::Address.secondary_address }
    shipping_city { Faker::Address.city }
    shipping_state { Faker::Address.state }
    shipping_zipcode { Faker::Address.zip_code }
    shipping_country { Faker::Address.country_code }
  end
end
