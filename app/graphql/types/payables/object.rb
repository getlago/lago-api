module Types
  module Payables
    class Object < Types::BaseUnion
      graphql_name 'Payable'

      possible_types Types::Payments::Object, Types::PaymentRequests::Object

      def self.resolve_type(object, _context)
        case object.class.to_s
        when 'Payment'
          Types::Payments::Object
        when 'PaymentRequest'
          Types::PaymentRequests::Object
        else
          raise "Unexpected payable type: #{object.inspect}"
        end
      end
    end
  end
end
