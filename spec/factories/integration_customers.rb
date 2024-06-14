# frozen_string_literal: true

FactoryBot.define do
  factory :netsuite_customer, class: 'IntegrationCustomers::NetsuiteCustomer' do
    association :integration, factory: :netsuite_integration
    customer
    type { 'IntegrationCustomers::NetsuiteCustomer' }
    external_customer_id { SecureRandom.uuid }

    settings do
      {sync_with_provider: true, subsidiary_id: Faker::Number.number(digits: 3)}
    end
  end

  factory :anrok_customer, class: 'IntegrationCustomers::AnrokCustomer' do
    association :integration, factory: :netsuite_integration
    customer
    type { 'IntegrationCustomers::AnrokCustomer' }
    external_customer_id { SecureRandom.uuid }

    settings do
      {sync_with_provider: true}
    end
  end

  factory :xero_customer, class: 'IntegrationCustomers::XeroCustomer' do
    association :integration, factory: :xero_integration
    customer
    type { 'IntegrationCustomers::XeroCustomer' }
    external_customer_id { SecureRandom.uuid }

    settings do
      {sync_with_provider: true}
    end
  end
end
