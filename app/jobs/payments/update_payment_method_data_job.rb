# frozen_string_literal: true

module Payments
  class UpdatePaymentMethodDataJob < ApplicationJob
    queue_as "default"

    def perform(provider_payment_id:, provider_payment_method_id:)
      payment = ::Payment.find_by!(provider_payment_id: provider_payment_id)
      ::Payments::UpdatePaymentMethodDataService.call!(payment:, provider_payment_method_id:)
    end
  end
end
