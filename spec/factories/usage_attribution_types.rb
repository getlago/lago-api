# frozen_string_literal: true

FactoryBot.define do
  factory :usage_attribution_type do
    organization
    sequence(:code) { |n| "usage-attribution-type-#{n}" }
    name { "User" }
    description { Faker::Lorem.sentence }
    sequence(:attribution_keys) { |n| ["attribution_key_#{n}"] }
    role { "hierarchical" }

    factory :flat_usage_attribution_type do
      name { "Model" }
      role { "flat" }
    end
  end
end
