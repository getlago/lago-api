# frozen_string_literal: true

FactoryBot.define do
  factory :product do
    organization
    name { Faker::Name.name }
    code { Faker::Alphanumeric.alphanumeric(number: 10) }
    description { Faker::Lorem.sentence }
    invoice_display_name { Faker::Fantasy::Tolkien.location }
  end
end
