# frozen_string_literal: true

FactoryBot.define do
  factory :order_form do
    customer
    organization { customer&.organization || association(:organization) }
    quote_version do
      association(:quote_version,
        organization:,
        quote: association(:quote, organization:, customer:))
    end
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
  end
end
