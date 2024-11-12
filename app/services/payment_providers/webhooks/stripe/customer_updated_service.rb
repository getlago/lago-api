# frozen_string_literal: true

module PaymentProviders
  module Webhooks
    module Stripe
      class CustomerUpdatedService < BaseService
        def call
          return handle_missing_customer unless stripe_customer

          PaymentProviderCustomers::Stripe::UpdatePaymentMethodService.call(
            stripe_customer:,
            payment_method_id: payment_method_id
          )
        rescue ActiveRecord::RecordInvalid => e
          result.record_validation_failure!(record: e.record)
        end

        private

        def stripe_customer_id
          event.data.object.id
        end

        def stripe_customer
          @stripe_customer ||= PaymentProviderCustomers::StripeCustomer
            .by_provider_id_from_organization(organization.id, stripe_customer_id)
            .first
        end

        def payment_method_id
          event.data.object.invoice_settings.default_payment_method || event.data.object.default_source
        end
      end
    end
  end
end
