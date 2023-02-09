# frozen_string_literal: true

module Customers
  class UpdateService < BaseService
    def update(**args)
      customer = result.user.customers.find_by(id: args[:id])
      return result.not_found_failure!(resource: 'customer') unless customer

      ActiveRecord::Base.transaction do
        billing_configuration = args[:billing_configuration]&.to_h || {}
        if args.key?(:currency)
          update_currency(customer:, currency: args[:currency], customer_update: true)
          return result unless result.success?
        end
        old_payment_provider = customer.payment_provider

        customer.name = args[:name] if args.key?(:name)
        customer.country = args[:country]&.upcase if args.key?(:country)
        customer.address_line1 = args[:address_line1] if args.key?(:address_line1)
        customer.address_line2 = args[:address_line2] if args.key?(:address_line2)
        customer.state = args[:state] if args.key?(:state)
        customer.zipcode = args[:zipcode] if args.key?(:zipcode)
        customer.email = args[:email] if args.key?(:email)
        customer.city = args[:city] if args.key?(:city)
        customer.url = args[:url] if args.key?(:url)
        customer.phone = args[:phone] if args.key?(:phone)
        customer.logo_url = args[:logo_url] if args.key?(:logo_url)
        customer.legal_name = args[:legal_name] if args.key?(:legal_name)
        customer.legal_number = args[:legal_number] if args.key?(:legal_number)

        assign_premium_attributes(customer, args)

        # TODO: delete this when GraphQL will use billing_configuration.
        customer.vat_rate = args[:vat_rate] if args.key?(:vat_rate)
        customer.payment_provider = args[:payment_provider] if args.key?(:payment_provider)
        customer.invoice_footer = args[:invoice_footer] if args.key?(:invoice_footer)

        if billing_configuration.key?(:document_locale)
          customer.document_locale = billing_configuration[:document_locale]
        end

        if License.premium? && args.key?(:invoice_grace_period)
          Customers::UpdateInvoiceGracePeriodService.call(customer:, grace_period: args[:invoice_grace_period])
        end

        if args.key?(:billing_configuration)
          billing = args[:billing_configuration]
          customer.invoice_footer = billing[:invoice_footer] if billing.key?(:invoice_footer)
          customer.vat_rate = billing[:vat_rate] if billing.key?(:vat_rate)

          if License.premium? && billing.key?(:invoice_grace_period)
            Customers::UpdateInvoiceGracePeriodService.call(customer:, grace_period: billing[:invoice_grace_period])
          end
        end

        # NOTE: external_id is not editable if customer is attached to subscriptions
        customer.external_id = args[:external_id] if customer.editable? && args.key?(:external_id)
        customer.save!

        # NOTE: if payment provider is updated, we need to create/update the provider customer
        payment_provider = old_payment_provider || customer.payment_provider
        create_or_update_provider_customer(customer, payment_provider, args[:provider_customer])
      end

      result.customer = customer
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    def update_currency(customer:, currency:, customer_update: false)
      return result if customer.currency == currency

      if customer_update
        # NOTE: direct update of the customer currency
        unless customer.editable?
          return result.single_validation_failure!(
            field: :currency,
            error_code: 'currencies_does_not_match',
          )
        end
      elsif customer.currency.present? || !customer.editable?
        # NOTE: Assign currency from another resource
        return result.single_validation_failure!(
          field: :currency,
          error_code: 'currencies_does_not_match',
        )
      end

      customer.update!(currency: currency)
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    def assign_premium_attributes(customer, args)
      return unless License.premium?

      customer.timezone = args[:timezone] if args.key?(:timezone)
    end

    def create_or_update_provider_customer(customer, payment_provider, billing_configuration = {})
      handle_provider_customer = customer.payment_provider.present?
      handle_provider_customer ||= (billing_configuration || {})[:provider_customer_id].present?

      case payment_provider
      when 'stripe'
        handle_provider_customer ||= customer.stripe_customer&.provider_customer_id.present?

        return unless handle_provider_customer

        update_stripe_customer(customer, billing_configuration)
      when 'gocardless'
        handle_provider_customer ||= customer.gocardless_customer&.provider_customer_id.present?

        return unless handle_provider_customer

        update_gocardless_customer(customer, billing_configuration)
      end
    end

    def update_stripe_customer(customer, billing_configuration)
      create_result = PaymentProviderCustomers::CreateService.new(customer).create_or_update(
        customer_class: PaymentProviderCustomers::StripeCustomer,
        payment_provider_id: customer.organization.stripe_payment_provider&.id,
        params: billing_configuration,
      )
      create_result.raise_if_error!

      # NOTE: Create service is modifying an other instance of the provider customer
      customer.stripe_customer&.reload
    end

    def update_gocardless_customer(customer, billing_configuration)
      create_result = PaymentProviderCustomers::CreateService.new(customer).create_or_update(
        customer_class: PaymentProviderCustomers::GocardlessCustomer,
        payment_provider_id: customer.organization.gocardless_payment_provider&.id,
        params: billing_configuration,
      )
      create_result.raise_if_error!

      # NOTE: Create service is modifying an other instance of the provider customer
      customer.gocardless_customer&.reload
    end
  end
end
