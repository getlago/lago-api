# frozen_string_literal: true

FactoryBot.define do
  factory :payment_provider_customer do
    customer

    external_customer_id { SecureRandom.uuid }
  end
end
