# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module PaymentIntents
  class ExpireJob < ApplicationJob
    queue_as "providers"

    retry_on ::Stripe::RateLimitError, ::Stripe::APIConnectionError, wait: :polynomially_longer, attempts: 5

    def perform(invoice)
      PaymentIntents::ExpireService.call!(invoice:)
    end
  end
end
