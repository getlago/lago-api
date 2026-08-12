# frozen_string_literal: true

FactoryBot.define do
  factory :rate_card_rate do
    organization
    rate_card { association(:rate_card, organization:) }
    sequence(:code) { |n| "rate#{n}" }
    # Midnight to match what the model canonicalizes arrears values to; the
    # factory's default card is arrears.
    effective_from { Time.current.beginning_of_day }
    rate_model { "standard" }
    rate_properties { {"amount" => "10"} }
    min_amount_cents { 0 }
    billing_interval_count { 1 }
    billing_interval_unit { "month" }
  end
end
