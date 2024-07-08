# frozen_string_literal: true

module Customers
  class UpdateService < BaseService
    include Customers::PaymentProviderFinder

    def update(**args)
      customer = result.user.customers.find_by(id: args[:id])
      return result.not_found_failure!(resource: 'customer') unless customer

      unless valid_metadata_count?(metadata: args[:metadata])
        return result.single_validation_failure!(
          field: :metadata,
          error_code: 'invalid_count'
        )
      end

      old_payment_provider = customer.payment_provider
      old_provider_customer = customer.provider_customer
      ActiveRecord::Base.transaction do
        billing_configuration = args[:billing_configuration]&.to_h || {}
        shipping_address = args[:shipping_address]&.to_h || {}

        if args.key?(:currency)
          update_currency(customer:, currency: args[:currency], customer_update: true)
          result.raise_if_error!
        end

        customer.name = args[:name] if args.key?(:name)
        customer.tax_identification_number = args[:tax_identification_number] if args.key?(:tax_identification_number)
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
        customer.net_payment_term = args[:net_payment_term] if args.key?(:net_payment_term)
        customer.external_salesforce_id = args[:external_salesforce_id] if args.key?(:external_salesforce_id)
        customer.shipping_address_line1 = shipping_address[:address_line1] if shipping_address.key?(:address_line1)
        customer.shipping_address_line2 = shipping_address[:address_line2] if shipping_address.key?(:address_line2)
        customer.shipping_city = shipping_address[:city] if shipping_address.key?(:city)
        customer.shipping_zipcode = shipping_address[:zipcode] if shipping_address.key?(:zipcode)
        customer.shipping_state = shipping_address[:state] if shipping_address.key?(:state)
        customer.shipping_country = shipping_address[:country]&.upcase if shipping_address.key?(:country)

        assign_premium_attributes(customer, args)

        customer.payment_provider = args[:payment_provider] if args.key?(:payment_provider)
        customer.payment_provider_code = args[:payment_provider_code] if args.key?(:payment_provider_code)
        customer.invoice_footer = args[:invoice_footer] if args.key?(:invoice_footer)

        if billing_configuration.key?(:document_locale)
          customer.document_locale = billing_configuration[:document_locale]
        end
      end

      if License.premium? && args.key?(:invoice_grace_period)
        Customers::UpdateInvoiceGracePeriodService.call(customer:, grace_period: args[:invoice_grace_period])
      end

      if args.key?(:billing_configuration)
        billing = args[:billing_configuration]
        customer.invoice_footer = billing[:invoice_footer] if billing.key?(:invoice_footer)

        if License.premium? && billing.key?(:invoice_grace_period)
          Customers::UpdateInvoiceGracePeriodService.call(customer:, grace_period: billing[:invoice_grace_period])
        end
      end

      if args.key?(:net_payment_term)
        Customers::UpdateInvoicePaymentDueDateService.call(customer:, net_payment_term: args[:net_payment_term])
      end

      # NOTE: external_id is not editable if customer is attached to subscriptions
      customer.external_id = args[:external_id] if customer.editable? && args.key?(:external_id)

      ActiveRecord::Base.transaction do
        if old_provider_customer && args[:payment_provider].nil? && args[:payment_provider_code].present?
          old_provider_customer.destroy!
          customer.payment_provider_code = nil
        end

        customer.save!
        customer = customer.reload

        if customer.organization.eu_tax_management
          eu_tax_code = Customers::EuAutoTaxesService.call(customer:)

          args[:tax_codes] ||= []
          args[:tax_codes] = (args[:tax_codes] + [eu_tax_code]).uniq
        end

        if args[:tax_codes]
          taxes_result = Customers::ApplyTaxesService.call(customer:, tax_codes: args[:tax_codes])
          taxes_result.raise_if_error!
        end
        Customers::Metadata::UpdateService.call(customer:, params: args[:metadata]) if args[:metadata]
      end

      # NOTE: if payment provider is updated, we need to create/update the provider customer
      if args.key?(:provider_customer) || args.key?(:payment_provider)
        payment_provider = old_payment_provider || customer.payment_provider
        create_or_update_provider_customer(customer, payment_provider, args[:provider_customer])
      end

      if args.dig(:provider_customer, :provider_customer_id)
        update_result = PaymentProviderCustomers::UpdateService.call(customer)
        update_result.raise_if_error!
      end

      result.customer = customer

      IntegrationCustomers::CreateOrUpdateService.call(
        integration_customers: args[:integration_customers],
        customer: result.customer,
        new_customer: false
      )

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    end

    def update_currency(customer:, currency:, customer_update: false)
      return result if customer.currency == currency

      if customer_update
        # NOTE: direct update of the customer currency
        unless customer.editable?
          return result.single_validation_failure!(
            field: :currency,
            error_code: 'currencies_does_not_match'
          )
        end
      elsif customer.currency.present? || !customer.editable?
        # NOTE: Assign currency from another resource
        return result.single_validation_failure!(
          field: :currency,
          error_code: 'currencies_does_not_match'
        )
      end

      customer.update!(currency:)
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    def valid_metadata_count?(metadata:)
      return true if metadata.blank?
      return true if metadata.count <= ::Metadata::CustomerMetadata::COUNT_PER_CUSTOMER

      false
    end

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
      when 'adyen'
        handle_provider_customer ||= customer.adyen_customer&.provider_customer_id.present?

        return unless handle_provider_customer

        update_adyen_customer(customer, billing_configuration)
      end
    end

    def update_stripe_customer(customer, billing_configuration)
      create_result = PaymentProviderCustomers::CreateService.new(customer).create_or_update(
        customer_class: PaymentProviderCustomers::StripeCustomer,
        payment_provider_id: payment_provider(customer)&.id,
        params: billing_configuration
      )
      create_result.raise_if_error!

      # NOTE: Create service is modifying an other instance of the provider customer
      customer.stripe_customer&.reload
    end

    def update_gocardless_customer(customer, billing_configuration)
      create_result = PaymentProviderCustomers::CreateService.new(customer).create_or_update(
        customer_class: PaymentProviderCustomers::GocardlessCustomer,
        payment_provider_id: payment_provider(customer)&.id,
        params: billing_configuration
      )
      create_result.raise_if_error!

      # NOTE: Create service is modifying an other instance of the provider customer
      customer.gocardless_customer&.reload
    end

    def update_adyen_customer(customer, billing_configuration)
      create_result = PaymentProviderCustomers::CreateService.new(customer).create_or_update(
        customer_class: PaymentProviderCustomers::AdyenCustomer,
        payment_provider_id: payment_provider(customer)&.id,
        params: billing_configuration
      )
      create_result.raise_if_error!

      # NOTE: Create service is modifying an other instance of the provider customer
      customer.adyen_customer&.reload
    end
  end
end
