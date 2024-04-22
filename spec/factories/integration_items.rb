# frozen_string_literal: true

FactoryBot.define do
  factory :integration_items do
    integration
    type { 'standard' }
    name { 'test name' }
    code { 'test_code' }
  end
end
