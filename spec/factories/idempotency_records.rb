# frozen_string_literal: true

FactoryBot.define do
  factory :idempotency_record do
    idempotency_key { SecureRandom.uuid }
    resource { nil }
  end
end
