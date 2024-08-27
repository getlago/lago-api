# frozen_string_literal: true

module PaymentRequests
  module Payments
    class AdyenCreateJob < ApplicationJob
      queue_as 'providers'

      unique :until_executed

      retry_on Faraday::ConnectionFailed, wait: :polynomially_longer, attempts: 6

      def perform(payable)
        result = PaymentRequests::Payments::AdyenService.new(payable).create
        result.raise_if_error!
      end
    end
  end
end
