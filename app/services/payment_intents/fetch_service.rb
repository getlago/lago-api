# frozen_string_literal: true

module PaymentIntents
  class FetchService < BaseService
    Result = BaseResult[:payment_intent]

    LOCK_TIMEOUT = 10.seconds

    def initialize(invoice:)
      @invoice = invoice
      super
    end

    def call
      return result.not_found_failure!(resource: "invoice") unless invoice

      # A concurrent request for the same invoice waits for this one, then reuses its intent and payment
      # URL instead of creating a second intent or payment link. The session lock opens no transaction,
      # so none stays open during the provider call.
      Invoice.with_advisory_lock!(lock_key, transaction: false, timeout_seconds: LOCK_TIMEOUT) do
        fetch_payment_intent
      end
    rescue WithAdvisoryLock::FailedToAcquireLock => e
      result.lock_acquisition_failure!(message: e.message, error: e)
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :invoice

    def lock_key
      "payment_intent_invoice_#{invoice.id}"
    end

    def fetch_payment_intent
      PaymentIntent.awaiting_expiration.find_by(invoice:)&.expired!
      payment_intent = PaymentIntent.non_expired.find_or_create_by!(invoice:, organization: invoice.organization)

      if payment_intent.payment_url.blank?
        payment_url_result = Invoices::Payments::PaymentProviders::Factory
          .for(invoice)
          .call!(:generate_payment_url, invoice, payment_intent)

        if payment_url_result.payment_url.blank?
          return result.single_validation_failure!(error_code: "payment_provider_error")
        end

        payment_intent.update!(
          payment_url: payment_url_result.payment_url,
          provider_session_id: payment_url_result.provider_session_id
        )
      end

      result.payment_intent = payment_intent
      result
    end
  end
end
