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
        # The service period is optional on a one_off item, and it is what the commercial term is
        # derived from. Specs that want a term pass both.
        add_on_from_datetime { nil }
        add_on_to_datetime { nil }
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
                "totalAmountCents" => 10_000,
                "fromDatetime" => add_on_from_datetime,
                "toDatetime" => add_on_to_datetime
              }
            }
          ]
        }
      end
    end

    trait :with_subscription_creation_billing_items do
      transient do
        plan { create(:plan, organization: quote.organization) }
        plan_start_date { Date.current.iso8601 }
        # Left blank on purpose: an ending date bounds the whole deal, see
        # QuoteVersions::DealExpiration. Specs that want that bound pass one.
        plan_end_date { nil }
      end

      currency { "EUR" }
      billing_items do
        {
          "plans" => [
            {
              "id" => plan.id,
              "localId" => SecureRandom.uuid,
              "type" => "plan",
              "payload" => {
                "code" => plan.code,
                "startDate" => plan_start_date,
                "endDate" => plan_end_date
              }.compact
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
