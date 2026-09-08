# frozen_string_literal: true

FactoryBot.define do
  factory :plan do
    organization
    name { Faker::TvShows::SiliconValley.app }
    invoice_display_name { Faker::TvShows::BreakingBad.episode }
    code { Faker::Alphanumeric.alphanumeric(number: 10) }
    description { Faker::Lorem.sentence }
    interval { "monthly" }
    pay_in_advance { false }
    amount_cents { 100 }
    amount_currency { "EUR" }

    trait :pay_in_advance do
      pay_in_advance { true }
    end

    trait :product_catalog do
      pricing_type { "product_catalog" }
      interval { nil }
      amount_cents { nil }
      pay_in_advance { nil }
    end
  end
end
