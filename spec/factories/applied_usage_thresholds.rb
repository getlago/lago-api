# frozen_string_literal: true

FactoryBot.define do
  factory :applied_usage_threshold do
    usage_threshold
    invoice

    lifetime_usage_amount_cents { 100 }
  end
end
