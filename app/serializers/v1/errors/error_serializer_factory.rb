# frozen_string_literal: true

module V1
  module Errors
    class ErrorSerializerFactory
      def self.new_instance(error)
        if error.is_a?(::Stripe::StripeError)
          V1::StripeErrorSerializer.new(error)
        else
          raise NotImplementedError
        end
      end
    end
  end
end
