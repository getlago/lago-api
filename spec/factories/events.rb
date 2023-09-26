# frozen_string_literal: true

FactoryBot.define do
  factory :event do
    organization_id { create(:organization).id }
    customer_id { create(:customer).id }
    subscription_id { create(:subscription).id }

    transaction_id { SecureRandom.uuid }
    code { Faker::Name.name.underscore }
    timestamp { Time.current }
  end
end
