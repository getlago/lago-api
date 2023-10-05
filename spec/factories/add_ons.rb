# frozen_string_literal: true

FactoryBot.define do
  factory :add_on do
    organization
    name { Faker::Name.name }
    invoice_display_name { Faker::Fantasy::Tolkien.location }
    code { Faker::Name.first_name }
    description { 'test description' }
    amount_cents { 200 }
    amount_currency { 'EUR' }
  end
end
