# frozen_string_literal: true

FactoryBot.define do
  factory :integration_resource do
    syncable { association(%i[invoice payment credit_note].sample, organization:) }
    association :integration, factory: :netsuite_integration
    organization { integration.organization }
    external_id { SecureRandom.uuid }
  end
end
