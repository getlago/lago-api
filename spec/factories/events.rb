# frozen_string_literal: true

FactoryBot.define do
  factory :event do
    transient do
      subscription { create(:subscription) }
      customer { subscription.customer }
    end

    organization_id { create(:organization).id }
    customer_id { customer.id }
    subscription_id { subscription.id }

    transaction_id { SecureRandom.uuid }
    code { Faker::Name.name.underscore }
    timestamp { Time.current }

    external_customer_id { customer.external_id }
    external_subscription_id { subscription.external_id }
  end
end
