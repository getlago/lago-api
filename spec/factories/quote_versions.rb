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
          "addOns" => [
            {
              "id" => add_on.id,
              "localId" => SecureRandom.uuid,
              "type" => "add_on",
              "payload" => {
                "code" => add_on.code,
                "units" => 1,
                "unitAmountCents" => 10_000,
                "totalAmountCents" => 10_000
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
