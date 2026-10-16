# frozen_string_literal: true

module PaymentProviders
  class CancelPaymentJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_PAYMENTS"])
        :payments
      else
        :providers
      end
    end

    retry_on ::Stripe::RateLimitError, wait: :polynomially_longer, attempts: 6
    retry_on ::Stripe::APIConnectionError, wait: :polynomially_longer, attempts: 6
    retry_on Invoices::Payments::ConnectionError, wait: :polynomially_longer, attempts: 6

    def perform(payment)
      PaymentProviders::CancelPaymentService.call!(payment:)
    end
  end
end
