# frozen_string_literal: true

FactoryBot.define do
  factory :billing_entity do
    name { Faker::Company.name }
    code { "entity_#{SecureRandom.uuid}" }
    default_currency { "USD" }

    email { Faker::Internet.email }
    email_settings { ["invoice.finalized", "credit_note.created"] }

    # TODO: remove this magic after is_default field is deleted
    # we need firstly to set is_default on the current billing_entity,
    # so when creating organization we won't need to create a default billing entity
    after :build do |billing_entity, values|
      billing_entity.is_default = true if values.organization&.billing_entities&.where(is_default: true).blank?
      billing_entity.organization = build(:organization, billing_entities: [billing_entity]) if values.organization.blank?
    end

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
