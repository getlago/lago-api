# frozen_string_literal: true

FactoryBot.define do
  factory :netsuite_customer, class: "IntegrationCustomers::NetsuiteCustomer" do
    integration { association(:netsuite_integration, organization:) }
    customer
    organization { customer.organization }
    type { "IntegrationCustomers::NetsuiteCustomer" }
    external_customer_id { SecureRandom.uuid }

    settings do
      {sync_with_provider: true, subsidiary_id: Faker::Number.number(digits: 3)}
    end
  end

  factory :anrok_customer, class: "IntegrationCustomers::AnrokCustomer" do
    integration { association(:anrok_integration, organization:) }
    customer
    organization { customer.organization }
    type { "IntegrationCustomers::AnrokCustomer" }
    external_customer_id { SecureRandom.uuid }

    settings do
      {sync_with_provider: true}
    end
  end

  factory :avalara_customer, class: "IntegrationCustomers::AvalaraCustomer" do
    integration { association(:avalara_integration, organization:) }
    customer
    organization { customer.organization }
    type { "IntegrationCustomers::AvalaraCustomer" }
    external_customer_id { SecureRandom.uuid }

    settings do
      {sync_with_provider: true}
    end
  end

  factory :xero_customer, class: "IntegrationCustomers::XeroCustomer" do
    integration { association(:xero_integration, organization:) }
    customer
    organization { customer.organization }
    type { "IntegrationCustomers::XeroCustomer" }
    external_customer_id { SecureRandom.uuid }

    settings do
      {sync_with_provider: true}
    end
  end

  factory :hubspot_customer, class: "IntegrationCustomers::HubspotCustomer" do
    integration { association(:hubspot_integration, organization:) }
    customer
    organization { customer.organization }
    type { "IntegrationCustomers::HubspotCustomer" }
    external_customer_id { SecureRandom.uuid }

    settings do
      {
        sync_with_provider: true,
        email: Faker::Internet.email,
        targeted_object: Integrations::HubspotIntegration::TARGETED_OBJECTS.sample
      }
    end
  end

  factory :salesforce_customer, class: "IntegrationCustomers::SalesforceCustomer" do
    integration { association(:salesforce_integration, organization:) }
    customer
    organization { customer.organization }
    type { "IntegrationCustomers::SalesforceCustomer" }
    external_customer_id { SecureRandom.uuid }
    settings { {} }
  end
end
