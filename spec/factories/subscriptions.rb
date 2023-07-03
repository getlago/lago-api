# frozen_string_literal: true

FactoryBot.define do
  factory :subscription do
    customer
    plan
    status { :active }
    external_id { SecureRandom.uuid }

    factory :active_subscription do
      status { :active }
      started_at { Time.zone.now }
    end

    factory :pending_subscription do
      status { :pending }
    end

    factory :terminated_subscription do
      status { :terminated }
      started_at { 1.month.ago }
      terminated_at { Time.zone.now }
    end
  end
end
