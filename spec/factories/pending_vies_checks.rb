# frozen_string_literal: true

FactoryBot.define do
  factory :pending_vies_check do
    organization {
      customer&.organization || billing_entity&.organization || association(:organization)
    }
    billing_entity { customer&.billing_entity || association(:billing_entity) }
    customer
    attempts_count { 0 }
    tax_identification_number { customer&.tax_identification_number || "EU123456789" }

    trait :failed do
      attempts_count { 3 }
      last_attempt_at { 1.hour.ago }
      last_error_message { "Network error" }
      last_error_type { "TimeoutError" }
    end
  end
end
