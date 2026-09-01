# frozen_string_literal: true

module CreditNotes
  module Refunds
    class StripeCreateJob < ApplicationJob
      queue_as "providers"

      # NOTE: safe to retry because stripe deduplicates on the idempotency key that
      #       Stripe::Refund.create sends (the credit note id), so a replayed request returns
      #       the original refund instead of issuing a second one. We enforce nothing on our
      #       side, and stripe only honours that key for 24h; the backoff below tops out around
      #       20 minutes, so raising `attempts` much further would void the guarantee.
      retry_on ::Stripe::RateLimitError, wait: :polynomially_longer, attempts: 6
      retry_on ::Stripe::APIConnectionError, wait: :polynomially_longer, attempts: 6

      def perform(credit_note)
        result = CreditNotes::Refunds::StripeService.new(credit_note).create
        result.raise_if_error!
      end
    end
  end
end
