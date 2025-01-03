# frozen_string_literal: true

module PaymentRequests
  module Payments
    class AdyenCreateJob < ApplicationJob
      queue_as 'providers'

      unique :until_executed, on_conflict: :log

      retry_on Faraday::ConnectionFailed, wait: :polynomially_longer, attempts: 6

      def perform(payable)
        # NOTE: Legacy job, kept only to avoid faileure with existing jobs

        PaymentRequests::Payments::CreateService.call!(payable:, payment_provider: 'adyen')
      end
    end
  end
end
