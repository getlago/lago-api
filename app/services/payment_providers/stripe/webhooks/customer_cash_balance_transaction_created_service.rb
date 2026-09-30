# frozen_string_literal: true

module PaymentProviders
  module Stripe
    module Webhooks
      class CustomerCashBalanceTransactionCreatedService < BaseService
        Result = BaseResult[:invoice]

        FUNDED_TYPE = "funded"

        def call
          return result unless funded?
          return result unless stripe_customer
          return result unless customer_balance_only?
          return result unless unallocated_funds?

          invoice = oldest_collectible_invoice
          return result unless invoice
          return result unless last_payment_failed?(invoice)

          Invoices::Payments::CreateJob.perform_later(invoice:, payment_provider: :stripe)

          result.invoice = invoice
          result
        end

        private

        def transaction
          event.data.object
        end

        def funded?
          transaction[:type] == FUNDED_TYPE
        end

        def stripe_customer
          return @stripe_customer if defined?(@stripe_customer)

          @stripe_customer = PaymentProviderCustomers::StripeCustomer
            .by_provider_id_from_organization(organization.id, transaction[:customer])
            .first
        end

        def customer_balance_only?
          stripe_customer.provider_payment_methods == ["customer_balance"]
        end

        def unallocated_funds?
          transaction[:ending_balance].to_i.positive?
        end

        def last_payment_failed?(invoice)
          last_payment = invoice
            .payments
            .where(payment_type: :provider)
            .order(:created_at, :id)
            .last

          last_payment&.payable_payment_status == "failed"
        end

        def oldest_collectible_invoice
          stripe_customer
            .customer
            .invoices
            .finalized
            .non_self_billed
            .where(payment_status: %w[pending failed], currency: currency)
            .order(:issuing_date, :created_at)
            .first
        end

        def currency
          transaction[:currency].to_s.upcase
        end
      end
    end
  end
end
