# frozen_string_literal: true

FactoryBot.define do
  factory :subscription_usage_activity, class: "Subscription::UsageActivity" do
    organization
    subscription

    recalculate_current_usage { false }
  end
end
