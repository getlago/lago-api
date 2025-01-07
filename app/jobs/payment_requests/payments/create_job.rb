# frozen_string_literal: true

module PaymentRequests
  module Payments
    class CreateJob < ApplicationJob
      queue_as 'providers'

      unique :until_executed, on_conflict: :log

      retry_on Faraday::ConnectionFailed, wait: :polynomially_longer, attempts: 6
      retry_on ::Stripe::RateLimitError, wait: :polynomially_longer, attempts: 6
      retry_on ::Stripe::APIConnectionError, wait: :polynomially_longer, attempts: 6

      def perform(payable:, payment_provider:)
        PaymentRequests::Payments::CreateService.call!(payable:, payment_provider:)
      end
    end
  end
end
