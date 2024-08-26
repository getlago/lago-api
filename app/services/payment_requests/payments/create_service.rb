# frozen_string_literal: true

module PaymentRequests
  module Payments
    class CreateService < BaseService
      def initialize(payable)
        @payable = payable

        super
      end

      def call
        case payment_provider
        when :adyen
          PaymentRequests::Payments::AdyenCreateJob.perform_later(payable)
        when :gocardless
          PaymentRequests::Payments::GocardlessCreateJob.perform_later(payable)
        when :stripe
          PaymentRequests::Payments::StripeCreateJob.perform_later(payable)
        end
      # TODO: Do something when no payment provider is set
      #       or leave it to the caller
      rescue ActiveJob::Uniqueness::JobNotUnique => e
        Sentry.capture_exception(e)
      end

      private

      attr_reader :payable

      def payment_provider
        payable.customer.payment_provider&.to_sym
      end
    end
  end
end
