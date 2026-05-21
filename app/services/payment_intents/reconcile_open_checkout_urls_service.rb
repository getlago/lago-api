# frozen_string_literal: true

module PaymentIntents
  # Reconciles every open hosted-checkout URL for an invoice against the
  # provider's view of it. Each URL ends up in one of two terminal states:
  #
  #   * customer already paid via the URL -> result.already_paid_via_checkout = true
  #     (the caller must stand down; the URL's webhook will finalize the invoice)
  #   * URL not paid -> expired locally and on the provider side
  #
  # Used by Invoices::Payments::CreateService before launching an automatic
  # charge, so an auto-charge cannot race a customer paying via the URL.
  class ReconcileOpenCheckoutUrlsService < BaseService
    Result = BaseResult[:already_paid_via_checkout]

    def initialize(invoice:)
      @invoice = invoice
      super
    end

    def call
      result.already_paid_via_checkout = false
      return result if invoice.blank?

      open_intents = PaymentIntent.active.where(invoice:).where.not(provider_session_id: nil)
      return result if open_intents.none?

      provider = Invoices::Payments::PaymentProviders::Factory.new_instance(invoice:)

      open_intents.find_each do |payment_intent|
        if provider.checkout_session_already_completed?(payment_intent)
          result.already_paid_via_checkout = true
          return result
        end

        begin
          provider.expire_checkout_session(payment_intent)
          payment_intent.expired!
        rescue => e
          # Don't block the auto-charge on a flaky provider. The intent stays
          # active so the trailing-edge ExpireOpenCheckoutUrlsJob (or the next
          # reconcile run) can retry. We log so operators see the trend.
          Rails.logger.warn(
            "ReconcileOpenCheckoutUrlsService: expire failed for " \
            "PaymentIntent #{payment_intent.id}: #{e.class}: #{e.message}"
          )
        end
      end

      result
    end

    private

    attr_reader :invoice
  end
end
