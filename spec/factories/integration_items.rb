# frozen_string_literal: true

FactoryBot.define do
  factory :integration_item do
    association :integration, factory: :netsuite_integration
    item_type { 'standard' }
    name { 'test name' }
    account_code { 'test_code' }
    external_id { SecureRandom.uuid }
  end
end
