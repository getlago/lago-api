# frozen_string_literal: true

module Types
  module PaymentProviders
    class Object < Types::BaseUnion
      graphql_name 'PaymentProvider'

      possible_types Types::PaymentProviders::Adyen,
        Types::PaymentProviders::Gocardless,
        Types::PaymentProviders::Stripe,
        Types::PaymentProviders::Cashfree

      def self.resolve_type(object, _context)
        case object.class.to_s
        when 'PaymentProviders::AdyenProvider'
          Types::PaymentProviders::Adyen
        when 'PaymentProviders::StripeProvider'
          Types::PaymentProviders::Stripe
        when 'PaymentProviders::GocardlessProvider'
          Types::PaymentProviders::Gocardless
        when 'PaymentProviders::CashfreeProvider'
          Types::PaymentProviders::Cashfree
        else
          raise "Unexpected Payment provider type: #{object.inspect}"
        end
      end
    end
  end
end
