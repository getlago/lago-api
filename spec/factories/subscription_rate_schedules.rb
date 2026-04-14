# frozen_string_literal: true

FactoryBot.define do
  factory :subscription_rate_schedule do
    organization
    subscription { association(:subscription, organization:) }
    product_item { association(:product_item, organization:) }
    rate_schedule { association(:rate_schedule, organization:, product_item:) }
    status { "active" }
    intervals_billed { 0 }
    started_at { Time.current }

    trait :with_cycles do
      transient do
        cycles_count { 1 }
        billing_anchor_date { nil }
      end

      after(:create) do |srs, evaluator|
        anchor = evaluator.billing_anchor_date
        current_from = srs.started_at

        evaluator.cycles_count.times do |i|
          if anchor && i == 0
            # Calendar billing: first cycle is a stub from started_at to billing_anchor_date
            create(:subscription_rate_schedule_cycle,
              organization: srs.organization,
              subscription_rate_schedule: srs,
              cycle_index: i,
              from_datetime: current_from,
              to_datetime: anchor.to_datetime)
            current_from = anchor.to_datetime
          else
            cycle = create(:subscription_rate_schedule_cycle,
              organization: srs.organization,
              subscription_rate_schedule: srs,
              cycle_index: i,
              from_datetime: current_from)
            current_from = cycle.to_datetime
          end
        end
      end
    end
  end
end
