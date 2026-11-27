# frozen_string_literal: true

FactoryBot.define do
  factory :billing_engine_migration do
    organization
    shadow_organization
    status { "shadowing" }
    plan_mapping { {} }

    trait :copying_from_raw_topic do
      events_copy_source { "raw_topic" }
      shadow_organization { association(:shadow_organization, clickhouse_events_store: true) }
    end
  end

  factory :shadow_organization, parent: :organization do
    feature_flags { ["product_catalog"] }
    webhook_url { nil }
    billing_entities do
      [association(:billing_entity, organization: instance, email_settings: [], strategy: :build)]
    end
  end
end
