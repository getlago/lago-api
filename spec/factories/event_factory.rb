# frozen_string_literal: true

FactoryBot.define do
  factory :event do
    organization
    customer

    transaction_id { SecureRandom.uuid }
    code { Faker::Name.name.underscore }
    timestamp { Time.current }
  end
end
