# frozen_string_literal: true

module Integrations
  module Aggregator
    module Payments
      class LockService < BaseLockService
        def initialize(payment:, timeout_seconds: ACQUIRE_LOCK_TIMEOUT, transaction: true)
          @payment = payment

          super(timeout_seconds:, transaction:)
        end

        private

        attr_reader :payment

        def lock_owner
          Payment
        end

        def lock_key
          "accounting-payment-sync-#{payment.id}"
        end
      end
    end
  end
end
