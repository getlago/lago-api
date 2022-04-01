# frozen_string_literal: true

FactoryBot.define do
  factory :plan do
    organization
    name { Faker::TvShows::SiliconValley.app }
    code { Faker::Name.name.underscore }
    frequency { 'monthly' }
    billing_period { 'beginning_of_period' }
    pro_rata { false }
    amount_cents { 100 }
    amount_currency { 'EUR' }
  end
end
