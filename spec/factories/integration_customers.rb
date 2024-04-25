# frozen_string_literal: true

FactoryBot.define do
  factory :netsuite_customer, class: 'IntegrationCustomers::NetsuiteCustomer' do
    association :integration, factory: :netsuite_integration
    customer
    type { 'IntegrationCustomers::NetsuiteCustomer' }
    external_customer_id { SecureRandom.uuid }

    settings do
      { sync_with_provider: true, subsidiary_id: Faker::Number.number(digits: 3) }
    end
  end
end
