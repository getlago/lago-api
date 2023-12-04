# frozen_string_literal: true

FactoryBot.define do
  factory :tax do
    organization
    code { "vat-#{SecureRandom.uuid}" }
    description { 'French Standard VAT' }
    name { 'VAT' }
    rate { 20.0 }
    applied_to_organization { true }
    auto_generated { false }
  end
end
