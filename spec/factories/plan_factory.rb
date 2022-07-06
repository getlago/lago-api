# frozen_string_literal: true

FactoryBot.define do
  factory :plan do
    organization
    name { Faker::TvShows::SiliconValley.app }
    code { Faker::Name.first_name }
    interval { 'monthly' }
    pay_in_advance { false }
    amount_cents { 100 }
    amount_currency { 'EUR' }
  end
end
