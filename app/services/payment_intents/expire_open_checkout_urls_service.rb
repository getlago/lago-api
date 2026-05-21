# frozen_string_literal: true

module PaymentIntents
  # Expires every open hosted-checkout URL for an invoice on the provider
  # side and marks the matching PaymentIntent as expired locally.
  #
  # Used after the invoice has already been paid (auto-charge succeeded, or
  # URL payment landed) to make sure no other open URL can be used to charge
  # the customer a second time. Unlike ReconcileOpenCheckoutUrlsService, this
  # does NOT check whether the URL was already paid first — the invoice is
  # already settled, so the "already paid" branch is information we don't
  # need to act on. Provider returns "not expirable" on already-paid URLs;
  # the per-provider rescue swallows it.
  class ExpireOpenCheckoutUrlsService < BaseService
    def initialize(invoice:)
      @invoice = invoice
      super
    end

    def call
      return result if invoice.blank?

      open_intents = PaymentIntent.active.where(invoice:).where.not(provider_session_id: nil)
      return result if open_intents.none?

      provider = Invoices::Payments::PaymentProviders::Factory.new_instance(invoice:)

      open_intents.find_each do |payment_intent|
        provider.expire_checkout_session(payment_intent)
        payment_intent.expired!
      end

      result
    end

    private

    attr_reader :invoice
  end
end
