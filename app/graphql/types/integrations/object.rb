# frozen_string_literal: true

module Types
  module Integrations
    class Object < Types::BaseUnion
      graphql_name 'Integration'

      possible_types Types::Integrations::Netsuite,
        Types::Integrations::Okta,
        Types::Integrations::Anrok,
        Types::Integrations::Xero

      def self.resolve_type(object, _context)
        case object.class.to_s
        when 'Integrations::NetsuiteIntegration'
          Types::Integrations::Netsuite
        when 'Integrations::OktaIntegration'
          Types::Integrations::Okta
        when 'Integrations::AnrokIntegration'
          Types::Integrations::Anrok
        when 'Integrations::XeroIntegration'
          Types::Integrations::Xero
        else
          raise "Unexpected integration type: #{object.inspect}"
        end
      end
    end
  end
end
