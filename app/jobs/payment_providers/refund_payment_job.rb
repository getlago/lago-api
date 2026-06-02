# frozen_string_literal: true

module PaymentProviders
  class RefundPaymentJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_PAYMENTS"])
        :payments
      else
        :providers
      end
    end

    def perform(payment, reason: nil)
      PaymentProviders::RefundPaymentService.call!(payment:, reason:)
    end
  end
end
