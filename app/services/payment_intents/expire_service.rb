# frozen_string_literal: true

module PaymentIntents
  class ExpireService < BaseService
    Result = BaseResult[:payment_intents]

    def initialize(invoice:)
      @invoice = invoice
      super
    end

    def call
      payment_intents = PaymentIntent.active.where(invoice:)

      payment_intents.find_each do |payment_intent|
        if payment_intent.provider_session_id.present?
          Invoices::Payments::PaymentProviders::Factory
            .for(invoice)
            .call!(:expire_payment_url, invoice, payment_intent)
        end

        # NOTE: also move expires_at into the past so the intent leaves the reuse window
        #       (PaymentIntent.non_expired is time-based) and a fresh intent is generated next time.
        payment_intent.update!(status: :expired, expires_at: Time.current)
      end

      result.payment_intents = payment_intents
      result
    end

    private

    attr_reader :invoice
  end
end
