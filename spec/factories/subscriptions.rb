# frozen_string_literal: true

FactoryBot.define do
  factory :subscription do
    customer
    plan
    status { :active }
    external_id { SecureRandom.uuid }
    started_at { 1.day.ago }

    trait :pending do
      status { :pending }
    end

    trait :terminated do
      status { :terminated }
      started_at { 1.month.ago }
      terminated_at { Time.zone.now }
    end

    trait :calendar do
      billing_time { :calendar }
    end
  end
end
