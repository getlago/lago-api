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
    association :integration, factory: :anrok_integration
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

  factory :hubspot_customer, class: 'IntegrationCustomers::HubspotCustomer' do
    association :integration, factory: :hubspot_integration
    customer
    type { 'IntegrationCustomers::HubspotCustomer' }
    external_customer_id { SecureRandom.uuid }

    settings do
      {
        sync_with_provider: true,
        email: Faker::Internet.email,
        targeted_object: Integrations::HubspotIntegration::TARGETED_OBJECTS.sample
      }
    end
  end

  factory :salesforce_customer, class: 'IntegrationCustomers::SalesforceCustomer' do
    association :integration, factory: :salesforce_integration
    customer
    type { 'IntegrationCustomers::HubspotCustomer' }
    external_customer_id { SecureRandom.uuid }

    settings do
      {
        sync_with_provider: false
      }
    end
  end
end
