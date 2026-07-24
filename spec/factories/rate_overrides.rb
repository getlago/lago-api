# frozen_string_literal: true

FactoryBot.define do
  factory :rate_override do
    organization
    rate_model { "standard" }
    rate_properties { {"amount" => "10"} }
    min_amount_cents { 0 }
    billing_interval_count { nil }
    billing_interval_unit { nil }
    pricing_unit_conversion_rate { nil }
  end
end
