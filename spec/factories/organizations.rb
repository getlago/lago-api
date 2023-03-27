# frozen_string_literal: true

FactoryBot.define do
  factory :organization do
    name { Faker::Company.name }
    vat_rate { 20 }
    webhook_url { Faker::Internet.url }
    email { Faker::Internet.email }
    email_settings { ['invoice.finalized', 'credit_note.created'] }
  end
end
