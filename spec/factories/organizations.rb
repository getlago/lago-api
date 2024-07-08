# frozen_string_literal: true

FactoryBot.define do
  factory :organization do
    name { Faker::Company.name }
    default_currency { 'USD' }

    email { Faker::Internet.email }
    email_settings { ['invoice.finalized', 'credit_note.created'] }

    transient do
      webhook_url { Faker::Internet.url }
    end

    after(:create) do |organization, evaluator|
      organization.webhook_endpoints.create(webhook_url: evaluator.webhook_url)
    end
  end
end
