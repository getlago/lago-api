# frozen_string_literal: true

FactoryBot.define do
  factory :organization do
    name { Faker::Company.name }
    default_currency { "USD" }

    email { Faker::Internet.email }
    email_settings { ["invoice.finalized", "credit_note.created"] }

    api_keys { [association(:api_key, organization: instance)] }
    billing_entities { [association(:billing_entity, organization: instance)] }

    transient do
      webhook_url { Faker::Internet.url }
    end

    after(:create) do |organization, evaluator|
      # because we're building billing entity while building the organization, possible that the billing_entity will be
      # created att he same moment as the organization, so we need to reload it to get the correct scope
      organization.reload
      if evaluator.webhook_url
        organization.webhook_endpoints.create!(webhook_url: evaluator.webhook_url)
      end
    end

    trait :premium do
      premium_integrations { Organization::PREMIUM_INTEGRATIONS }
    end

    trait :with_invoice_custom_sections do
      after :create do |org|
        create_list(:invoice_custom_section, 3, organization: org)
      end
    end

    trait :with_default_dunning_campaign do
      after :create do |org|
        create(:dunning_campaign, organization: org, applied_to_organization: true)
      end
    end
  end
end
