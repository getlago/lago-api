# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    email { Faker::Internet.email }
    password { "ILoveLago" }

    trait :self_serve do
      self_serve_verified_at { Time.current }
    end
  end
end
