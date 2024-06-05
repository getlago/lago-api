# frozen_string_literal: true

module Customers
  class CreateService < BaseService
    include Customers::PaymentProviderFinder

    def create_from_api(organization:, params:)
      customer = organization.customers.find_or_initialize_by(external_id: params[:external_id])
      new_customer = customer.new_record?

      unless valid_metadata_count?(metadata: params[:metadata])
        return result.single_validation_failure!(
          field: :metadata,
          error_code: 'invalid_count'
        )
      end

      ActiveRecord::Base.transaction do
        customer.name = params[:name] if params.key?(:name)
        customer.country = params[:country]&.upcase if params.key?(:country)
        customer.address_line1 = params[:address_line1] if params.key?(:address_line1)
        customer.address_line2 = params[:address_line2] if params.key?(:address_line2)
        customer.state = params[:state] if params.key?(:state)
        customer.zipcode = params[:zipcode] if params.key?(:zipcode)
        customer.email = params[:email] if params.key?(:email)
        customer.city = params[:city] if params.key?(:city)
        customer.url = params[:url] if params.key?(:url)
        customer.phone = params[:phone] if params.key?(:phone)
        customer.logo_url = params[:logo_url] if params.key?(:logo_url)
        customer.legal_name = params[:legal_name] if params.key?(:legal_name)
        customer.legal_number = params[:legal_number] if params.key?(:legal_number)
        customer.net_payment_term = params[:net_payment_term] if params.key?(:net_payment_term)
        customer.external_salesforce_id = params[:external_salesforce_id] if params.key?(:external_salesforce_id)
        if params.key?(:tax_identification_number)
          customer.tax_identification_number = params[:tax_identification_number]
        end

        assign_premium_attributes(customer, params)

        if params.key?(:currency)
          currency_result = Customers::UpdateService.new(nil).update_currency(
            customer:,
            currency: params[:currency],
            customer_update: true
          )
          return currency_result unless currency_result.success?
        end

        ActiveRecord::Base.transaction do
          customer.save!

          if customer.organization.eu_tax_management
            eu_tax_code = Customers::EuAutoTaxesService.call(customer:)

            params[:tax_codes] ||= []
            params[:tax_codes] = (params[:tax_codes] + [eu_tax_code]).uniq
          end

          if params[:tax_codes].present?
            taxes_result = Customers::ApplyTaxesService.call(customer:, tax_codes: params[:tax_codes])
            taxes_result.raise_if_error!
          end

          if new_customer && params[:metadata]
            params[:metadata].each { |m| create_metadata(customer:, args: m) }
          elsif params[:metadata]
            Customers::Metadata::UpdateService.call(customer:, params: params[:metadata])
          end
        end
      end

      # NOTE: handle configuration for configured payment providers
      handle_api_billing_configuration(customer, params, new_customer)

      result.customer = customer.reload

      IntegrationCustomers::CreateOrUpdateService.call(
        integration_customer_params: params[:integration_customer],
        customer: result.customer,
        new_customer:,
      )

      track_customer_created(customer)
      result
    rescue BaseService::ServiceFailure => e
      result.single_validation_failure!(error_code: e.code)
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
    end

    def create(**args)
      billing_configuration = args[:billing_configuration]&.to_h || {}

      unless valid_metadata_count?(metadata: args[:metadata])
        return result.single_validation_failure!(
          field: :metadata,
          error_code: 'invalid_count'
        )
      end

      customer = Customer.new(
        organization_id: args[:organization_id],
        external_id: args[:external_id],
        name: args[:name],
        country: args[:country]&.upcase,
        address_line1: args[:address_line1],
        address_line2: args[:address_line2],
        state: args[:state],
        zipcode: args[:zipcode],
        email: args[:email],
        city: args[:city],
        url: args[:url],
        phone: args[:phone],
        logo_url: args[:logo_url],
        legal_name: args[:legal_name],
        legal_number: args[:legal_number],
        net_payment_term: args[:net_payment_term],
        external_salesforce_id: args[:external_salesforce_id],
        vat_rate: args[:vat_rate],
        payment_provider: args[:payment_provider],
        payment_provider_code: args[:payment_provider_code],
        currency: args[:currency],
        document_locale: billing_configuration[:document_locale],
        tax_identification_number: args[:tax_identification_number]
      )

      assign_premium_attributes(customer, args)

      ActiveRecord::Base.transaction do
        customer.save!

        if customer.organization.eu_tax_management
          eu_tax_code = Customers::EuAutoTaxesService.call(customer:)

          args[:tax_codes] ||= []
          args[:tax_codes] = (args[:tax_codes] + [eu_tax_code]).uniq
        end

        if args[:tax_codes].present?
          taxes_result = Customers::ApplyTaxesService.call(customer:, tax_codes: args[:tax_codes])
          taxes_result.raise_if_error!
        end

        args[:metadata].each { |m| create_metadata(customer:, args: m) } if args[:metadata].present?
      end

      # NOTE: handle configuration for configured payment providers
      billing_configuration = args[:provider_customer]&.to_h&.merge(
        payment_provider: args[:payment_provider],
        payment_provider_code: args[:payment_provider_code]
      )
      create_billing_configuration(customer, billing_configuration)

      result.customer = customer

      IntegrationCustomers::CreateOrUpdateService.call(
        integration_customer_params: args[:integration_customer]&.to_h,
        customer: result.customer,
        new_customer: true,
      )

      track_customer_created(customer)
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

    def create_metadata(customer:, args:)
      customer.metadata.create!(
        key: args[:key],
        value: args[:value],
        display_in_invoice: args[:display_in_invoice] || false
      )
    end

    def assign_premium_attributes(customer, args)
      return unless License.premium?

      customer.timezone = args[:timezone] if args.key?(:timezone)
      customer.invoice_grace_period = args[:invoice_grace_period] if args.key?(:invoice_grace_period)
    end

    def create_billing_configuration(customer, billing_configuration = {})
      return if billing_configuration.blank? || (api_context? && billing_configuration[:payment_provider].nil?)

      create_provider_customer = billing_configuration[:sync_with_provider]
      create_provider_customer ||= billing_configuration[:provider_customer_id]
      return unless create_provider_customer

      if api_context?
        customer.payment_provider = billing_configuration[:payment_provider]

        payment_provider_result = PaymentProviders::FindService.new(
          organization_id: customer.organization_id,
          code: billing_configuration[:payment_provider_code].presence,
          payment_provider_type: customer.payment_provider
        ).call
        payment_provider_result.raise_if_error!

        customer.payment_provider_code = payment_provider_result.payment_provider.code
        customer.save!
      end

      create_or_update_provider_customer(customer, billing_configuration)
    end

    def handle_api_billing_configuration(customer, params, new_customer)
      params[:billing_configuration] = {} unless params.key?(:billing_configuration)

      billing = params[:billing_configuration]

      if License.premium? && billing.key?(:invoice_grace_period)
        Customers::UpdateInvoiceGracePeriodService.call(customer:, grace_period: billing[:invoice_grace_period])
      end

      # NOTE(legacy): keep accepting vat_rate field temporary by converting it into tax
      handle_legacy_vat_rate(customer:, vat_rate: billing[:vat_rate]) if billing.key?(:vat_rate)

      customer.document_locale = billing[:document_locale] if billing.key?(:document_locale)

      if new_customer || should_create_billing_configuration?(billing, customer)
        create_billing_configuration(customer, billing)
        customer.save!
        return
      end

      if billing.key?(:payment_provider)
        customer.payment_provider = nil
        if %w[stripe gocardless adyen].include?(billing[:payment_provider])
          customer.payment_provider = billing[:payment_provider]
        end
      end

      customer.save!

      return if customer.payment_provider.nil?

      update_provider_customer = (billing || {})[:provider_customer_id].present?
      update_provider_customer ||= customer.provider_customer&.provider_customer_id.present?

      return unless update_provider_customer

      create_or_update_provider_customer(customer, billing)

      if customer.provider_customer&.provider_customer_id
        PaymentProviderCustomers::UpdateService.call(customer)
      end
    end

    def create_or_update_provider_customer(customer, billing_configuration = {})
      provider_class = case billing_configuration[:payment_provider] || customer.payment_provider
      when 'stripe'
        PaymentProviderCustomers::StripeCustomer
      when 'gocardless'
        PaymentProviderCustomers::GocardlessCustomer
      when 'adyen'
        PaymentProviderCustomers::AdyenCustomer
      end

      create_result = PaymentProviderCustomers::CreateService.new(customer).create_or_update(
        customer_class: provider_class,
        payment_provider_id: payment_provider(customer)&.id,
        params: billing_configuration,
        async: !(billing_configuration || {})[:sync]
      )

      create_result.raise_if_error!
    end

    def track_customer_created(customer)
      SegmentTrackJob.perform_later(
        membership_id: CurrentContext.membership,
        event: 'customer_created',
        properties: {
          customer_id: customer.id,
          created_at: customer.created_at,
          payment_provider: customer.payment_provider,
          organization_id: customer.organization_id
        }
      )
    end

    def handle_legacy_vat_rate(customer:, vat_rate:)
      if customer.taxes.count > 1
        result.single_validation_failure!(
          field: :vat_rate,
          error_code: 'multiple_taxes'
        ).raise_if_error!
      end

      # NOTE(legacy): Keep updating vat_rate until we remove the field
      customer.vat_rate = vat_rate

      current_tax = customer.taxes.first
      return if current_tax&.rate == vat_rate

      tax = customer.organization.taxes
        .create_with(rate: vat_rate, name: "Tax (#{vat_rate}%)")
        .find_or_create_by!(code: "tax_#{vat_rate}")

      Customers::ApplyTaxesService.call(customer:, tax_codes: [tax.code])
    end

    def should_create_billing_configuration?(billing, customer)
      billing[:sync_with_provider] && customer.provider_customer&.provider_customer_id.nil?
    end
  end
end
