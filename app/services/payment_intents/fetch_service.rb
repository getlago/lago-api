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
      payment_intent = find_or_create_payment_intent

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
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :invoice

    # A concurrent request can create the active intent between the find and the create:
    # the unique index on the active intent then rejects ours, and we reuse theirs.
    def find_or_create_payment_intent
      PaymentIntent.transaction(requires_new: true) do
        PaymentIntent.non_expired.find_or_create_by!(invoice:, organization: invoice.organization)
      end
    rescue ActiveRecord::RecordNotUnique
      PaymentIntent.active.non_expired.find_by!(invoice:)
    end
  end
end
