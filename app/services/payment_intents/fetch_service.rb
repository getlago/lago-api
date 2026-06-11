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

      if stripe_provider? && provider_payment_in_progress?
        # An off-session provider payment is already pending, processing or succeeded
        # for this invoice. Generating a hosted checkout would let the customer pay a
        # second time, so we don't offer one.
        # NOTE: scoped to Stripe for now; other providers get this in their own PR.
        return result.single_validation_failure!(error_code: "payment_already_processing")
      end

      PaymentIntent.awaiting_expiration.find_by(invoice:)&.expired!
      payment_intent = PaymentIntent.non_expired.find_or_create_by!(invoice:, organization: invoice.organization)

      if payment_intent.payment_url.blank?
        payment_url_result = Invoices::Payments::PaymentProviders::Factory
          .new_instance(invoice:)
          .generate_payment_url(payment_intent)

        payment_url_result.raise_if_error!

        if payment_url_result.payment_url.blank?
          return result.single_validation_failure!(error_code: "payment_provider_error")
        end

        payment_intent.update!(
          payment_url: payment_url_result.payment_url,
          provider_payment_url_id: payment_url_result.try(:payment_url_id)
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

    def stripe_provider?
      invoice.customer.payment_provider == "stripe"
    end

    def provider_payment_in_progress?
      invoice.payments
        .where(payment_type: :provider, payable_payment_status: %i[pending processing succeeded])
        .exists?
    end
  end
end
