# frozen_string_literal: true

FactoryBot.define do
  factory :payment_intent do
    invoice { association(:invoice) }
    payment_url { Faker::Internet.url }

    trait :expired do
      status { :expired }
      expires_at { generate(:past_date) }
    end
  end
end
