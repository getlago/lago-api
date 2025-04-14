# frozen_string_literal: true

module Payments
  class UpdatePaymentMethodDataJob < ApplicationJob
    queue_as "default"

    # NOTE: Even if the perform method is protected against running this job multple time
    unique :until_executed

    retry_on ::Stripe::RateLimitError, wait: :polynomially_longer, attempts: 5

    def perform(payment:, provider_payment_method_id:)
      ::Payments::UpdatePaymentMethodDataService.call!(payment:, provider_payment_method_id:)
    end
  end
end
