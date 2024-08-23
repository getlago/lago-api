# frozen_string_literal: true

FactoryBot.define do
  factory :applied_usage_threshold do
    usage_threshold
    invoice
  end
end
