# frozen_string_literal: true

FactoryBot.define do
  factory :tax_rate do
    organization
    code { "vat-#{SecureRandom.uuid}" }
    description { 'French Standard VAT' }
    name { 'VAT' }
    value { 20.0 }
    applied_by_default { true }
  end
end
