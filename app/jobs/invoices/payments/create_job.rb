# frozen_string_literal: true

module Invoices
  module Payments
    class CreateJob < ApplicationJob
      queue_as 'low_priority'

      unique :until_executed, on_conflict: :log

      retry_on Invoices::Payments::ConnectionError, wait: :polynomially_longer, attempts: 6
      retry_on Invoices::Payments::RateLimitError, wait: :polynomially_longer, attempts: 6

      def perform(invoice:, payment_provider:)
        Invoices::Payments::CreateService.call!(invoice:, payment_provider:)
      end
    end
  end
end
