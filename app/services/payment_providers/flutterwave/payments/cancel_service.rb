# frozen_string_literal: true

module PaymentProviders
  module Flutterwave
    module Payments
      class CancelService < BaseService
        Result = BaseResult[:payment]

        def initialize(payment:)
          @payment = payment

          super
        end

        def call
          result.payment = payment

          # Flutterwave does not support cancelling transactions via API.
          # Payments are created as checkout sessions and are either completed or expire.
          # This is a no-op for best-effort cancellation.
          result
        end

        private

        attr_reader :payment
      end
    end
  end
end
