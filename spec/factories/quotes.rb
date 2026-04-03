# frozen_string_literal: true

FactoryBot.define do
  factory :quote do
    organization
    customer
    number { "OF-2025-0001" }
    sequential_id { 1 }
    version { 1 }
    status { :draft }
    order_type { :subscription_creation }
    void_reason { nil }
    share_token { SecureRandom.uuid }
  end
end
