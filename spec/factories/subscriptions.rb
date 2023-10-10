# frozen_string_literal: true

FactoryBot.define do
  factory :subscription do
    customer
    plan
    status { :active }
    external_id { SecureRandom.uuid }

    factory :active_subscription do
      status { :active }
      started_at { 1.day.ago }
    end

    factory :pending_subscription do
      status { :pending }
    end

    trait :terminated do
      status { :terminated }
      started_at { 1.month.ago }
      terminated_at { Time.zone.now }
    end
  end
end
