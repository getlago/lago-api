# frozen_string_literal: true

module PaymentRequests
  module Payments
    module PaymentProviders
      class Factory
        def self.new_instance(payable:)
          service_class(payable.customer&.payment_provider).new(payable)
        end

        def self.service_class(payment_provider)
          case payment_provider&.to_s
          when 'stripe'
            PaymentRequests::Payments::StripeService
           when 'adyen'
             PaymentRequests::Payments::AdyenService
           when 'gocardless'
             PaymentRequests::Payments::GocardlessService
          else
            raise(NotImplementedError)
          end
        end
      end
    end
  end
end
