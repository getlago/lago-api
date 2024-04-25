# frozen_string_literal: true

module Types
  module IntegrationCustomers
    class Object < Types::BaseUnion
      graphql_name 'IntegrationCustomer'

      possible_types IntegrationCustomers::Netsuite

      def self.resolve_type(object, _context)
        case object.class.to_s
        when 'IntegrationCustomers::NetsuiteCustomer'
          Types::IntegrationCustomers::Netsuite
        else
          raise "Unexpected integration customer type: #{object.inspect}"
        end
      end
    end
  end
end
