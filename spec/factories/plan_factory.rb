# frozen_string_literal: true

FactoryBot.define do
  factory :plan do
    organization
    name { Faker::TvShows::SiliconValley.app }
    code { Faker::Name.name.underscore }
    interval { 'monthly' }
    pay_in_advance { false }
    amount_cents { 100 }
    amount_currency { 'EUR' }
    vat_rate { 20 }
  end
end
