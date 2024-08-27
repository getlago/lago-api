# frozen_string_literal: true

module PaymentRequests
  module Payments
    class CreateService < BaseService
      def initialize(payable)
        @payable = payable

        super
      end

      def call
        return result.not_found_failure!(resource: "payment_provider") unless payment_provider

        case payment_provider
        when :adyen
          PaymentRequests::Payments::AdyenCreateJob.perform_later(payable)
        when :gocardless
          PaymentRequests::Payments::GocardlessCreateJob.perform_later(payable)
        when :stripe
          PaymentRequests::Payments::StripeCreateJob.perform_later(payable)
        end
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
