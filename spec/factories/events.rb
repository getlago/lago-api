# frozen_string_literal: true

FactoryBot.define do
  factory :event do
    transient do
      subscription { create(:subscription) }
      customer { subscription.customer }
    end

    organization_id { create(:organization).id }

    transaction_id { SecureRandom.uuid }
    code { Faker::Name.name.underscore }
    timestamp { Time.current }

    external_customer_id { customer.external_id }
    external_subscription_id { subscription.external_id }
  end

  factory :received_event, class: 'Event' do
    transient do
      source_organization { create(:organization) }
      source_customer { create(:customer, organization: source_organization) }
      source_subscription do
        create(
          :subscription,
          customer: source_customer,
          organization: source_organization
        )
      end
    end

    organization_id { source_organization.id }
    external_customer_id { source_customer.external_id }
    external_subscription_id { source_subscription.external_id }

    transaction_id { SecureRandom.uuid }
    code { Faker::Name.name.underscore }
    timestamp { Time.current }
  end
end
