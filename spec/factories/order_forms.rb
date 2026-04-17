# frozen_string_literal: true

FactoryBot.define do
  factory :order_form do
    customer
    organization { customer&.organization || association(:organization) }
    quote { association(:quote, customer:, organization:) }
    billing_snapshot { {items: []} }
    status { :generated }

    trait :signed do
      status { :signed }
      signed_at { Time.current }
      signed_by_user_id { association(:user).id }
    end

    trait :expired do
      status { :expired }
      expires_at { 1.day.ago }
      voided_at { Time.current }
      void_reason { :expired }
    end

    trait :voided do
      status { :voided }
      voided_at { Time.current }
      void_reason { :manual }
    end

    trait :expiring_tomorrow do
      expires_at { 1.day.from_now }
    end

    trait :expired_yesterday do
      expires_at { 1.day.ago }
    end
  end
end
