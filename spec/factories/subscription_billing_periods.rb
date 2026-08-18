# frozen_string_literal: true

FactoryBot.define do
  factory :subscription_billing_period do
    transient do
      subscription { create(:subscription) }
    end

    organization { subscription.organization }
    customer { subscription.customer }
    subscription_id { subscription.id }
    scope_type { "Subscription" }
    scope_id { subscription.id }
    period_from { Time.current.beginning_of_month }
    period_to { Time.current.end_of_month }
  end
end
