# frozen_string_literal: true

FactoryBot.define do
  factory :organization do
    name { Faker::Company.name }
    default_currency { 'USD' }

    email { Faker::Internet.email }
    email_settings { ['invoice.finalized', 'credit_note.created'] }

    api_keys { [association(:api_key)] }

    transient do
      webhook_url { Faker::Internet.url }
    end

    after(:create) do |organization, evaluator|
      if evaluator.webhook_url
        organization.webhook_endpoints.create!(webhook_url: evaluator.webhook_url)
      end
    end

    trait :with_invoice_custom_sections do
      after :create do |org|
        sections = []
        3.times do
          sections << create(:invoice_custom_section, organization: org)
        end
        org.invoice_custom_section_selections = sections
      end
    end
  end
end
