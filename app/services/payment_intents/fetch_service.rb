# frozen_string_literal: true

module PaymentIntents
  class FetchService < BaseService
    Result = BaseResult[:payment_intent]

    def initialize(invoice:)
      @invoice = invoice
      super
    end

    def call
      return result.not_found_failure!(resource: "invoice") unless invoice

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
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    # A concurrent request created the active intent first. Retried, the request uses it.
    rescue ActiveRecord::RecordNotUnique => e
      raise unless violated_unique_index(e) == "index_payment_intents_on_invoice_id_and_status"

      result.lock_acquisition_failure!(message: e.message, error: e)
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :invoice
  end
end
