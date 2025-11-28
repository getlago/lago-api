# frozen_string_literal: true

module PaymentProviders
  module Stripe
    class CancelPaymentIntentJob < ApplicationJob
      queue_as do
        if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_PAYMENTS"])
          :payments
        else
          :providers
        end
      end

      def perform(organization_id:, provider_payment_id:)
        payment = Payment.find_by(organization_id:, provider_payment_id:)

        PaymentProviders::Stripe::Payments::CancelPaymentService.call!(payment_provider: payment.payment_provider, payment_intent_id: provider_payment_id)
      end
    end
  end
end
