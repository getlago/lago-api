# frozen_string_literal: true

FactoryBot.define do
  factory :billing_entity do
    organization
    name { Faker::Company.name }
    code { "entity_#{SecureRandom.uuid}" }
    default_currency { "USD" }

    email { Faker::Internet.email }
    email_settings { ["invoice.finalized", "credit_note.created"] }

    trait :default do
      is_default { true }
    end

    trait :deleted do
      deleted_at { Time.current }
    end

    trait :archived do
      archived_at { Time.current }
    end
  end
end
