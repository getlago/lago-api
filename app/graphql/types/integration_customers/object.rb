# frozen_string_literal: true

module Types
  module IntegrationCustomers
    class Object < Types::BaseUnion
      graphql_name "IntegrationCustomer"

      possible_types Types::IntegrationCustomers::Anrok,
        Types::IntegrationCustomers::Avalara,
        Types::IntegrationCustomers::Hubspot,
        Types::IntegrationCustomers::Netsuite,
        Types::IntegrationCustomers::Salesforce,
        Types::IntegrationCustomers::Xero

      def self.resolve_type(object, _context)
        case object.class.to_s
        when "IntegrationCustomers::AnrokCustomer"
          Types::IntegrationCustomers::Anrok
        when "IntegrationCustomers::AvalaraCustomer"
          Types::IntegrationCustomers::Avalara
        when "IntegrationCustomers::HubspotCustomer"
          Types::IntegrationCustomers::Hubspot
        when "IntegrationCustomers::NetsuiteCustomer"
          Types::IntegrationCustomers::Netsuite
        when "IntegrationCustomers::SalesforceCustomer"
          Types::IntegrationCustomers::Salesforce
        when "IntegrationCustomers::XeroCustomer"
          Types::IntegrationCustomers::Xero
        else
          raise "Unexpected integration customer type: #{object.inspect}"
        end
      end
    end
  end
end
