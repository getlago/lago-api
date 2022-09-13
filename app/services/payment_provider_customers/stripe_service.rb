# frozen_string_literal: true

module PaymentProviderCustomers
  class StripeService < BaseService
    def initialize(stripe_customer = nil)
      @stripe_customer = stripe_customer

      super(nil)
    end

    def create
      result.stripe_customer = stripe_customer
      return result if stripe_customer.provider_customer_id?

      stripe_result = create_stripe_customer

      stripe_customer.update!(
        provider_customer_id: stripe_result.id,
      )

      deliver_success_webhook

      result.stripe_customer = stripe_customer
      result
    end

    def update_payment_method(organization_id:, stripe_customer_id:, payment_method_id:)
      stripe_customer = PaymentProviderCustomers::StripeCustomer
        .joins(:customer)
        .where(customers: { organization_id: organization_id })
        .find_by(provider_customer_id: stripe_customer_id)
      return result.not_found_failure!(resource: 'stripe_customer') unless stripe_customer

      stripe_customer.payment_method_id = payment_method_id
      stripe_customer.save!

      reprocess_pending_invoices(customer)

      result.stripe_customer = stripe_customer
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    def delete_payment_method(organization_id:, stripe_customer_id:, payment_method_id:)
      stripe_customer = PaymentProviderCustomers::StripeCustomer
        .joins(:customer)
        .where(customers: { organization_id: organization_id })
        .find_by(provider_customer_id: stripe_customer_id)
      return result.not_found_failure!(resource: 'stripe_customer') unless stripe_customer

      # NOTE: check if payment_method was the default one
      stripe_customer.payment_method_id = nil if stripe_customer.payment_method_id == payment_method_id

      result.stripe_customer = stripe_customer
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    def check_payment_method(payment_method_id)
      payment_method = Stripe::Customer.new(id: stripe_customer.provider_customer_id)
        .retrieve_payment_method(payment_method_id, {}, { api_key: api_key })

      result.payment_method = payment_method
      result
    rescue Stripe::InvalidRequestError
      # NOTE: The payment method is no longer valid
      stripe_customer.update!(payment_method_id: nil)

      result.fail!(code: 'invalid_payment_method')
    end

    private

    attr_accessor :stripe_customer

    delegate :customer, to: :stripe_customer

    def organization
      customer.organization
    end

    def api_key
      organization.stripe_payment_provider.secret_key
    end

    def create_stripe_customer
      Stripe::Customer.create(
        stripe_create_payload,
        {
          api_key: api_key,
          idempotency_key: customer.id,
        },
      )
    rescue Stripe::InvalidRequestError => e
      deliver_error_webhook(e)

      raise
    end

    def stripe_create_payload
      {
        address: {
          city: customer.city,
          country: customer.country,
          line1: customer.address_line1,
          line2: customer.address_line2,
          postal_code: customer.zipcode,
          state: customer.state,
        },
        email: customer.email,
        name: customer.name,
        metadata: {
          lago_customer_id: customer.id,
          customer_id: customer.external_id,
        },
        phone: customer.phone,
      }
    end

    def deliver_success_webhook
      return unless customer.organization.webhook_url?

      SendWebhookJob.perform_later(
        :payment_provider_customer_created,
        customer,
      )
    end

    def deliver_error_webhook(stripe_error)
      return unless customer.organization.webhook_url?

      SendWebhookJob.perform_later(
        :payment_provider_customer_error,
        customer,
        provider_error: {
          message: stripe_error.message,
          error_code: stripe_error.code,
        },
      )
    end

    def reprocess_pending_invoices(customer)
      customer.invoices.pending.find_each do |invoice|
        Invoices::Payments::StripeCreateJob.perform_later(invoice)
      end
    end
  end
end
