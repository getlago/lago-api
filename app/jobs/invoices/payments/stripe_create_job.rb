# frozen_string_literal: true

module Invoices
  module Payments
    class StripeCreateJob < ApplicationJob
      queue_as 'providers'

      unique :until_executed, on_conflict: :log

      retry_on ::Stripe::RateLimitError, wait: :polynomially_longer, attempts: 6
      retry_on ::Stripe::APIConnectionError, wait: :polynomially_longer, attempts: 6

      def perform(invoice)
        # NOTE: Legacy job, kept only to avoid existing jobs
        #
        result = Invoices::Payments::StripeService.call(invoice)
        result.raise_if_error!
      end
    end
  end
end
