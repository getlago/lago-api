# frozen_string_literal: true

FactoryBot.define do
  factory :subscription do
    customer
    plan
    status { :active }

    factory :active_subscription do
      status { :active }
      started_at { Time.zone.now }
    end

    factory :pending_subscription do
      status { :pending }
    end
  end
end
