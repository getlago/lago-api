# frozen_string_literal: true

FactoryBot.define do
  factory :organization do
    name { Faker::Company.name }
    default_currency { "USD" }

    email { Faker::Internet.email }
    email_settings { ["invoice.finalized", "credit_note.created"] }

    api_keys { [association(:api_key, organization: instance)] }

    transient do
      webhook_url { Faker::Internet.url }
    end

    after(:create) do |organization, evaluator|
      if evaluator.webhook_url
        organization.webhook_endpoints.create!(webhook_url: evaluator.webhook_url)
      end
      # default billing entity on organization will be used in services as intermediate sep
      # before we start accepting billing_entity_id in the request. After that we can drop the column and this method
      if organization.billing_entities.where(is_default: true).blank?
        create(:billing_entity, :default, organization:)
      end
    end

    trait :with_invoice_custom_sections do
      after :create do |org|
        sections = create_list(:invoice_custom_section, 3, organization: org)
        org.invoice_custom_section_selections = sections
      end
    end

    trait :with_default_dunning_campaign do
      after :create do |org|
        create(:dunning_campaign, organization: org, applied_to_organization: true)
      end
    end
  end
end
