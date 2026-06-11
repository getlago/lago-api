# frozen_string_literal: true

module PaymentIntents
  class ExpireService < BaseService
    Result = BaseResult[:payment_intent, :checkout_paid]

    def initialize(invoice:)
      @invoice = invoice
      super
    end

    def call
      return result.not_found_failure!(resource: "invoice") unless invoice

      payment_intent = PaymentIntent.non_expired.find_by(invoice:, status: :active)
      return result unless payment_intent
      return result if payment_intent.provider_payment_url_id.blank?

      result.payment_intent = payment_intent

      provider_result = Invoices::Payments::PaymentProviders::Factory
        .new_instance(invoice:)
        .expire_payment_url(payment_intent)
      provider_result.raise_if_error!

      result.checkout_paid = provider_result.checkout_paid || false

      # When the customer is already paying through the hosted checkout we keep the
      # payment intent active so the checkout webhook can finalize the invoice.
      payment_intent.expire! unless result.checkout_paid

      result
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :invoice
  end
end
