# frozen_string_literal: true

module PaymentIntents
  class ExpireOpenCheckoutUrlsJob < ApplicationJob
    queue_as "default"

    retry_on Invoices::Payments::ConnectionError, wait: :polynomially_longer, attempts: 6
    retry_on Invoices::Payments::RateLimitError, wait: :polynomially_longer, attempts: 6

    def perform(invoice)
      PaymentIntents::ExpireOpenCheckoutUrlsService.call!(invoice:)
    end
  end
end
