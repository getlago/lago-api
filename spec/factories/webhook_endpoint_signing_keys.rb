# frozen_string_literal: true

FactoryBot.define do
  factory :webhook_endpoint_signing_key do
    webhook_endpoint
    organization { webhook_endpoint&.organization || association(:organization) }

    trait :expired do
      expires_at { 1.hour.ago }
    end

    trait :expiring do
      expires_at { 1.hour.from_now }
    end
  end
end
