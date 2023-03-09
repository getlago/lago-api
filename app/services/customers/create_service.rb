# frozen_string_literal: true

module Customers
  class CreateService < BaseService
    def create_from_api(organization:, params:)
      customer = organization.customers.find_or_initialize_by(external_id: params[:external_id])
      new_customer = customer.new_record?

      unless valid_metadata_count?(metadata: params[:metadata])
        return result.single_validation_failure!(
          field: :metadata,
          error_code: 'invalid_count',
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

        assign_premium_attributes(customer, params)

        if params.key?(:currency)
          currency_result = Customers::UpdateService.new(nil).update_currency(
            customer:,
            currency: params[:currency],
            customer_update: true,
          )
          return currency_result unless currency_result.success?
        end

        ActiveRecord::Base.transaction do
          customer.save!

          if new_customer && params[:metadata]
            params[:metadata].each { |m| create_metadata(customer:, args: m) }
          elsif params[:metadata]
            Customers::Metadata::UpdateService.call(customer:, params: params[:metadata])
          end
        end
      end

      # NOTE: handle configuration for configured payment providers
      handle_api_billing_configuration(customer, params, new_customer)

      result.customer = customer
      track_customer_created(customer)
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    def create(**args)
      billing_configuration = args[:billing_configuration]&.to_h || {}

      unless valid_metadata_count?(metadata: args[:metadata])
        return result.single_validation_failure!(
          field: :metadata,
          error_code: 'invalid_count',
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
        vat_rate: args[:vat_rate],
        payment_provider: args[:payment_provider],
        currency: args[:currency],
        document_locale: billing_configuration[:document_locale],
      )

      assign_premium_attributes(customer, args)

      ActiveRecord::Base.transaction do
        customer.save!

        args[:metadata].each { |m| create_metadata(customer:, args: m) } if args[:metadata].present?
      end

      # NOTE: handle configuration for configured payment providers
      billing_configuration = args[:provider_customer]&.to_h&.merge(payment_provider: args[:payment_provider])
      create_billing_configuration(customer, billing_configuration)

      result.customer = customer
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
        display_in_invoice: args[:display_in_invoice] || false,
      )
    end

    def assign_premium_attributes(customer, args)
      return unless License.premium?

      customer.timezone = args[:timezone] if args.key?(:timezone)
      customer.invoice_grace_period = args[:invoice_grace_period] if args.key?(:invoice_grace_period)
    end

    def create_billing_configuration(customer, billing_configuration = {})
      return if billing_configuration.blank?

      create_provider_customer = billing_configuration[:sync_with_provider]
      create_provider_customer ||= billing_configuration[:provider_customer_id]
      return unless create_provider_customer

      customer.update!(payment_provider: billing_configuration[:payment_provider]) if api_context?

      create_or_update_provider_customer(customer, billing_configuration)
    end

    def handle_api_billing_configuration(customer, params, new_customer)
      return unless params.key?(:billing_configuration)

      billing = params[:billing_configuration]

      if License.premium? && billing.key?(:invoice_grace_period)
        Customers::UpdateInvoiceGracePeriodService.call(customer:, grace_period: billing[:invoice_grace_period])
      end

      customer.vat_rate = billing[:vat_rate] if billing.key?(:vat_rate)
      customer.document_locale = billing[:document_locale] if billing.key?(:document_locale)

      if new_customer
        create_billing_configuration(customer, billing)
        return
      end

      if billing.key?(:payment_provider)
        customer.payment_provider = nil
        if %w[stripe gocardless].include?(billing[:payment_provider])
          customer.payment_provider = billing[:payment_provider]
        end
      end

      customer.save!

      return if customer.payment_provider.nil?

      create_or_update_provider_customer(customer, billing)
    end

    def create_or_update_provider_customer(customer, billing_configuration = {})
      provider_class = case billing_configuration[:payment_provider] || customer.payment_provider
                       when 'stripe'
                         PaymentProviderCustomers::StripeCustomer
                       when 'gocardless'
                         PaymentProviderCustomers::GocardlessCustomer
      end

      create_result = PaymentProviderCustomers::CreateService.new(customer).create_or_update(
        customer_class: provider_class,
        payment_provider_id: customer.organization.payment_provider(billing_configuration[:payment_provider])&.id,
        params: billing_configuration,
        async: !(billing_configuration || {})[:sync],
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
          organization_id: customer.organization_id,
        },
      )
    end
  end
end
