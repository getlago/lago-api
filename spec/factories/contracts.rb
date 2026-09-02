# frozen_string_literal: true

FactoryBot.define do
  factory :contract do
    customer
    organization { customer&.organization || association(:organization) }
    plan { nil }
    status { :active }
    external_id { SecureRandom.uuid }
    billing_time { :calendar }
    started_at { 1.day.ago }

    trait :pending do
      status { :pending }
      started_at { 1.day.from_now }
    end

    trait :terminated do
      status { :terminated }
      terminated_at { Time.current }
    end

    trait :canceled do
      status { :canceled }
      canceled_at { Time.current }
    end
  end
end
