# frozen_string_literal: true

module PaymentProviders
  class CancelPaymentJob < ApplicationJob
    queue_as "default"

    def perform(payment)
      PaymentProviders::CancelPaymentService.call!(payment:)
    end
  end
end
