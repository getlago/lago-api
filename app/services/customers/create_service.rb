# frozen_string_literal: true

module Customers
  class CreateService < BaseService
    include Customers::PaymentProviderFinder

    def create_from_api(organization:, params:)
      customer = organization.customers.find_or_initialize_by(external_id: params[:external_id])
      new_customer = customer.new_record?
      shipping_address = params[:shipping_address] ||= {}

      unless valid_metadata_count?(metadata: params[:metadata])
        return result.single_validation_failure!(
          field: :metadata,
          error_code: "invalid_count"
        )
      end

      unless valid_finalize_zero_amount_invoice?(params[:finalize_zero_amount_invoice])
        return result.single_validation_failure!(
          field: :finalize_zero_amount_invoice,
          error_code: "invalid_value"
        )
      end

      unless valid_integration_customers_count?(integration_customers: params[:integration_customers])
        return result.single_validation_failure!(
          field: :integration_customers,
          error_code: "invalid_count_per_integration_type"
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
        customer.shipping_address_line1 = shipping_address[:address_line1] if shipping_address.key?(:address_line1)
        customer.shipping_address_line2 = shipping_address[:address_line2] if shipping_address.key?(:address_line2)
        customer.shipping_city = shipping_address[:city] if shipping_address.key?(:city)
        customer.shipping_zipcode = shipping_address[:zipcode] if shipping_address.key?(:zipcode)
        customer.shipping_state = shipping_address[:state] if shipping_address.key?(:state)
        customer.shipping_country = shipping_address[:country]&.upcase if shipping_address.key?(:country)
        customer.url = params[:url] if params.key?(:url)
        customer.phone = params[:phone] if params.key?(:phone)
        customer.logo_url = params[:logo_url] if params.key?(:logo_url)
        customer.legal_name = params[:legal_name] if params.key?(:legal_name)
        customer.legal_number = params[:legal_number] if params.key?(:legal_number)
        customer.net_payment_term = params[:net_payment_term] if params.key?(:net_payment_term)
        customer.external_salesforce_id = params[:external_salesforce_id] if params.key?(:external_salesforce_id)
        customer.finalize_zero_amount_invoice = params[:finalize_zero_amount_invoice] || "inherit" if params.key?(:finalize_zero_amount_invoice)
        customer.firstname = params[:firstname] if params.key?(:firstname)
        customer.lastname = params[:lastname] if params.key?(:lastname)
        customer.customer_type = params[:customer_type] if params.key?(:customer_type)
        if params.key?(:tax_identification_number)
          customer.tax_identification_number = params[:tax_identification_number]
        end

        assign_premium_attributes(customer, params)

        if params.key?(:currency)
          Customers::UpdateCurrencyService
            .call(customer:, currency: params[:currency], customer_update: true)
            .raise_if_error!
        end

        customer.save!

        if customer.organization.eu_tax_management
          eu_tax_code = Customers::EuAutoTaxesService.call(customer:)

          params[:tax_codes] ||= []
          params[:tax_codes] = (params[:tax_codes] + [eu_tax_code]).uniq
        end

        if params.key?(:tax_codes)
          taxes_result = Customers::ApplyTaxesService.call(customer:, tax_codes: params[:tax_codes])
          taxes_result.raise_if_error!
        end

        Customers::ManageInvoiceCustomSectionsService.call(
          customer:,
          skip_invoice_custom_sections: params[:skip_invoice_custom_sections],
          section_codes: params[:invoice_custom_section_codes]
        ).raise_if_error!

        if new_customer && params[:metadata]
          params[:metadata].each { |m| create_metadata(customer:, args: m) }
        elsif params[:metadata]
          Customers::Metadata::UpdateService.call(customer:, params: params[:metadata])
        end
      end

      # NOTE: handle configuration for configured payment providers
      handle_api_billing_configuration(customer, params, new_customer)

      result.customer = customer.reload

      IntegrationCustomers::CreateOrUpdateService.call(
        integration_customers: params[:integration_customers],
        customer: result.customer,
        new_customer:
      )

      if new_customer
        SendWebhookJob.perform_later('customer.created', customer)
      else
        SendWebhookJob.perform_later('customer.updated', customer)
      end

      track_customer_created(customer)
      result
    rescue BaseService::ServiceFailure => e
      result.single_validation_failure!(error_code: e.code)
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
    rescue ActiveRecord::RecordNotUnique
      result.single_validation_failure!(field: :external_id, error_code: "value_already_exist")
    end

    def create(**args)
      billing_configuration = args[:billing_configuration]&.to_h || {}
      shipping_address = args[:shipping_address]&.to_h || {}

      unless valid_metadata_count?(metadata: args[:metadata])
        return result.single_validation_failure!(
          field: :metadata,
          error_code: "invalid_count"
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
        shipping_address_line1: shipping_address[:address_line1],
        shipping_address_line2: shipping_address[:address_line2],
        shipping_country: shipping_address[:country]&.upcase,
        shipping_state: shipping_address[:state],
        shipping_zipcode: shipping_address[:zipcode],
        shipping_city: shipping_address[:city],
        email: args[:email],
        city: args[:city],
        url: args[:url],
        phone: args[:phone],
        logo_url: args[:logo_url],
        legal_name: args[:legal_name],
        legal_number: args[:legal_number],
        net_payment_term: args[:net_payment_term],
        external_salesforce_id: args[:external_salesforce_id],
        payment_provider: args[:payment_provider],
        payment_provider_code: args[:payment_provider_code],
        currency: args[:currency],
        document_locale: billing_configuration[:document_locale],
        tax_identification_number: args[:tax_identification_number],
        firstname: args[:firstname],
        lastname: args[:lastname],
        customer_type: args[:customer_type]
      )

      if args.key?(:finalize_zero_amount_invoice)
        customer.finalize_zero_amount_invoice = args[:finalize_zero_amount_invoice]
      end

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
        integration_customers: args[:integration_customers],
        customer: result.customer,
        new_customer: true
      )

      SendWebhookJob.perform_later('customer.created', customer)
      track_customer_created(customer)
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    def valid_finalize_zero_amount_invoice?(value)
      return true if value.nil?
      Customer::FINALIZE_ZERO_AMOUNT_INVOICE_OPTIONS.include?(value.to_sym)
    end

    def valid_metadata_count?(metadata:)
      return true if metadata.blank?
      return true if metadata.count <= ::Metadata::CustomerMetadata::COUNT_PER_CUSTOMER

      false
    end

    def valid_integration_customers_count?(integration_customers:)
      return true if integration_customers.blank?

      input_types = integration_customers&.map { |c| c.to_h.deep_symbolize_keys }&.map { |c| c[:integration_type] }

      input_types.length == input_types.uniq.length
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

      customer.document_locale = billing[:document_locale] if billing.key?(:document_locale)

      if new_customer || should_create_billing_configuration?(billing, customer)
        create_billing_configuration(customer, billing)
        customer.save!
        return
      end

      if billing.key?(:payment_provider)
        customer.payment_provider = nil
        if Customer::PAYMENT_PROVIDERS.include?(billing[:payment_provider])
          customer.payment_provider = billing[:payment_provider]
          customer.payment_provider_code = billing[:payment_provider_code] if billing.key?(:payment_provider_code)
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
      PaymentProviders::CreateCustomerFactory.new_instance(
        provider: billing_configuration[:payment_provider] || customer.payment_provider,
        customer:,
        payment_provider_id: payment_provider(customer)&.id,
        params: billing_configuration,
        async: !(billing_configuration || {})[:sync]
      ).call.raise_if_error!
    end

    def track_customer_created(customer)
      SegmentTrackJob.perform_later(
        membership_id: CurrentContext.membership,
        event: "customer_created",
        properties: {
          customer_id: customer.id,
          created_at: customer.created_at,
          payment_provider: customer.payment_provider,
          organization_id: customer.organization_id
        }
      )
    end

    def should_create_billing_configuration?(billing, customer)
      (billing[:sync_with_provider] || billing[:provider_customer_id].present?) && customer.provider_customer&.provider_customer_id.nil?
    end
  end
end
