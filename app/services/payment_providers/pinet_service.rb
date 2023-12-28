# frozen_string_literal: true

module PaymentProviders
  class PinetService < BaseService
    def create_or_update(**args)
      pinet_provider = PaymentProviders::StripeProvider.find_or_initialize_by(
        organization_id: args[:organization_id],
      )

      secret_key = pinet_provider.secret_key

      pinet_provider.secret_key = args[:secret_key] if args.key?(:secret_key)
      pinet_provider.create_customers = args[:create_customers] if args.key?(:create_customers)
      pinet_provider.success_redirect_url = args[:success_redirect_url] if args.key?(:success_redirect_url)
      pinet_provider.save!

      if secret_key != pinet_provider.secret_key

        # PaymentProviders::Stripe::RegisterWebhookJob.perform_later(stripe_provider)

        # NOTE: ensure existing payment_provider_customers are
        #       attached to the provider
        reattach_provider_customers(
          organization_id: args[:organization_id],
          pinet_provider:,
        )
      end

      result.pinet_provider = pinet_provider
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    def reattach_provider_customers(organization_id:, pinet_provider:)
      PaymentProviderCustomers::PinetCustomer
        .joins(:customer)
        .where(payment_provider_id: nil, customers: { organization_id: })
        .update_all(payment_provider_id: pinet_provider.id)
    end
  end
end
