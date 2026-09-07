# frozen_string_literal: true

FactoryBot.define do
  factory :plan_rate_card do
    organization
    plan { association(:plan, organization:) }
    rate_card { association(:rate_card, organization:) }
    units { nil }
  end
end
