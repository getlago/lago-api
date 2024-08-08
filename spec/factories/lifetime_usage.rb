# frozen_string_literal: true

FactoryBot.define do
  factory :lifetime_usage do
    transient do
      customer { create(:customer, organization:) }
      subscription { create(:subscription, customer:) }
    end

    organization { subscription.organization }
    external_subscription_id { subscription.external_id }
    currency { "EUR" }
    current_usage_amount_cents { 0 }
    invoiced_usage_amount_cents { 0 }
    recalculate_current_usage { false }
    recalculate_invoiced_usage { false }
  end
end
