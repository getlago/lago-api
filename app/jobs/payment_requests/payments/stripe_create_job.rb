# frozen_string_literal: true

module PaymentRequests
  module Payments
    class StripeCreateJob < ApplicationJob
      queue_as 'providers'

      unique :until_executed, on_conflict: :log

      retry_on Stripe::RateLimitError, wait: :polynomially_longer, attempts: 6
      retry_on Stripe::APIConnectionError, wait: :polynomially_longer, attempts: 6

      def perform(payable)
        result = PaymentRequests::Payments::StripeService.new(payable).create
        result.raise_if_error!
      end
    end
  end
end
