# frozen_string_literal: true

module PaymentRequests
  module Payments
    class CreateService < BaseService
      def initialize(payable:, payment_provider: nil)
        @payable = payable
        @provider = payment_provider&.to_sym

        super
      end

      def call
        return result.not_found_failure!(resource: "payment_provider") unless provider

        payment_result = case provider
        when :adyen
          PaymentRequests::Payments::AdyenService.new(payable).create
        when :gocardless
          PaymentRequests::Payments::GocardlessService.new(payable).create
        when :stripe
          PaymentRequests::Payments::StripeService.new(payable).create
        end

        if payment_result.payable&.payment_failed?
          PaymentRequestMailer.with(payment_request: payable).requested.deliver_later
        end

        payment_result
      rescue ActiveJob::Uniqueness::JobNotUnique => e
        Sentry.capture_exception(e)
      end

      def call_async
        return result.not_found_failure!(resource: "payment_provider") unless provider

        PaymentRequests::Payments::CreateJob.perform_later(payable:, payment_provider: provider)

        result.payment_provider = provider
        result
      end

      private

      attr_reader :payable

      def provider
        @provider ||= payable.customer.payment_provider&.to_sym
      end
    end
  end
end
