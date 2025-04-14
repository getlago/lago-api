# frozen_string_literal: true

module Payments
  class UpdatePaymentMethodDataJob < ApplicationJob
    queue_as "default"

    # NOTE: Even if the service is protected against running multiple time, this job must be unique.
    #       https://github.com/getlago/lago-api/pull/3490
    unique :until_executed

    retry_on ::Stripe::RateLimitError, wait: :polynomially_longer, attempts: 5

    def perform(payment:, provider_payment_method_id:)
      ::Payments::UpdatePaymentMethodDataService.call!(payment:, provider_payment_method_id:)

      # Now that the payment method is saved in the payment, we generate the PaymentReceipt
      if payment.customer.organization.issue_receipts_enabled?
        PaymentReceipts::CreateJob.perform_later(payment)
      end
    end
  end
end
