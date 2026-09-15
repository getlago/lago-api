# frozen_string_literal: true

FactoryBot.define do
  factory :usage_attribution_value do
    customer
    organization { customer.organization }
    usage_attribution_type { association :usage_attribution_type, organization: }
    sequence(:value) { |n| "usage-attribution-value-#{n}" }
    last_seen_at { Time.current }
  end
end
