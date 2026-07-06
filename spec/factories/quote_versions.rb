# frozen_string_literal: true

FactoryBot.define do
  factory :quote_version do
    quote
    organization { quote.organization }
    status { :draft }
    sequence(:sequential_id) { |n| n }

    trait :approved do
      status { :approved }
      approved_at { Time.current }
    end

    trait :with_one_off_billing_items do
      transient do
        add_on { create(:add_on, organization: quote.organization) }
      end

      currency { "EUR" }
      billing_items do
        {
          "addons" => [
            {
              "id" => add_on.id,
              "local_id" => SecureRandom.uuid,
              "payload" => {
                "code" => add_on.code,
                "units" => 1,
                "unit_amount_cents" => 10_000,
                "total_amount_cents" => 10_000
              }
            }
          ]
        }
      end
    end

    trait :voided do
      status { :voided }
      voided_at { Time.current }
      void_reason { :manual }
    end
  end
end
