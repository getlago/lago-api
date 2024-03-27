# frozen_string_literal: true

FactoryBot.define do
  factory :membership do
    user
    organization
    role { "admin" }

    trait :revoked do
      status { :revoked }
      revoked_at { Time.current }
    end
  end
end
