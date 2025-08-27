# frozen_string_literal: true

FactoryBot.define do
  factory :job_schedule_override do
    organization
    job_name { "Clock::SchedulededFakeJob" }
    frequency_seconds { 120 }
    last_enqueued_at { nil }
    enabled_at { "2025-08-12 11:56:36" }

    trait :disabled do
      enabled_at { nil }
    end

    trait :last_enqueued do
      last_enqueued_at { "2025-08-12 11:56:36" }
    end
  end
end
