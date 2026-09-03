# frozen_string_literal: true

FactoryBot.define do
  factory :record_deletion do
    organization
    record_table { "fees" }
    record_id { SecureRandom.uuid }
    deleted_at { Time.current }
  end
end
