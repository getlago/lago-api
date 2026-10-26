# frozen_string_literal: true

module Payments
  class SetPaymentMethodAndCreateReceiptJob < ApplicationJob
    queue_as "default"

    # NOTE: Even if the service is protected against running multiple time, this job must be unique.
    #       https://github.com/getlago/lago-api/pull/3490
    unique :until_executed, on_conflict: :log

    retry_on ::Stripe::RateLimitError, wait: :polynomially_longer, attempts: 5

    def perform(payment:, provider_payment_method_id:)
      set_payment_method(payment:, provider_payment_method_id:)

      ::Payments::SetPaymentMethodDataService.call!(payment:, provider_payment_method_id:)

      # Now that the payment method is saved in the payment, we generate the PaymentReceipt
      if payment.customer.organization.issue_receipts_enabled?
        PaymentReceipts::CreateJob.perform_later(payment)
      end
    end

    private

    def set_payment_method(payment:, provider_payment_method_id:)
      return if provider_payment_method_id.blank?

      payment_method = payment.customer.payment_methods.find_by(provider_method_id: provider_payment_method_id)
      payment_method ||= find_or_create_stripe_payment_method(payment:, provider_payment_method_id:)

      if payment_method.present?
        payment.payment_method = payment_method
        payment.save!
      end
    end

    # A card used on a Stripe payment link is attached to the Stripe customer but unknown to Lago.
    # It is saved as a Lago payment method only when Stripe attached it to the customer's Stripe customer.
    def find_or_create_stripe_payment_method(payment:, provider_payment_method_id:)
      stripe_customer = stripe_customer_for(payment)
      return if stripe_customer&.provider_customer_id.blank?
      return unless payment.payment_provider.is_a?(PaymentProviders::StripeProvider)

      stripe_payment_method = ::Stripe::PaymentMethod.retrieve(
        provider_payment_method_id,
        {api_key: payment.payment_provider.secret_key}
      )
      return unless stripe_payment_method_customer_id(stripe_payment_method) == stripe_customer.provider_customer_id

      payment_method = PaymentMethods::FindOrCreateFromProviderService.call!(
        customer: payment.customer,
        payment_provider_customer: stripe_customer,
        provider_method_id: provider_payment_method_id,
        params: {provider_payment_methods: [stripe_payment_method.type]},
        set_as_default_on_create: false
      ).payment_method

      if payment_method.present?
        PaymentMethods::SetAsDefaultService.call!(payment_method:, only_when_no_default: true).payment_method
      end
    end

    def stripe_customer_for(payment)
      provider_customer = payment.payment_provider_customer

      if provider_customer.is_a?(PaymentProviderCustomers::StripeCustomer) && provider_customer.customer_id == payment.customer_id
        provider_customer
      else
        payment.customer.stripe_customer
      end
    end

    def stripe_payment_method_customer_id(stripe_payment_method)
      customer = stripe_payment_method.customer
      customer.is_a?(String) ? customer : customer&.id
    end
  end
end
