# frozen_string_literal: true

FactoryBot.define do
  factory :billing_engine_migration do
    organization
    shadow_organization
    status { "shadowing" }
    plan_mapping { {} }

    trait :copying_from_raw_topic do
      events_copy_source { "raw_topic" }
    end
  end

  factory :shadow_organization, parent: :organization do
    feature_flags { ["product_catalog"] }
    clickhouse_events_store { true }
    webhook_url { nil }
    billing_entities do
      [association(:billing_entity, organization: instance, email_settings: [], strategy: :build)]
    end
  end
end
