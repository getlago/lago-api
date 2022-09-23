# frozen_string_literal: true

module Customers
  class CreateService < BaseService
    def create_from_api(organization:, params:)
      customer = organization.customers.find_or_initialize_by(external_id: params[:external_id])
      new_customer = customer.new_record?

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
        customer.vat_rate = params[:vat_rate] if params.key?(:vat_rate)

        if params.key?(:currency)
          currency_result = Customers::UpdateService.new(nil).update_currency(
            customer: customer,
            currency: params[:currency],
            customer_update: true,
          )
          return currency_result unless currency_result.success?
        end

        customer.save!
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
      customer = Customer.create!(
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
      )

      # NOTE: handle configuration for configured payment providers
      create_billing_configuration(customer, args[:stripe_customer])

      result.customer = customer
      track_customer_created(customer)
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    # NOTE: Check if a payment provider is configured in the organization and
    #       force creation of provider customers
    def create_billing_configuration(customer, billing_configuration = {})
      create_stripe_customer = customer.organization.stripe_payment_provider&.create_customers
      create_stripe_customer ||= (billing_configuration || {})[:provider_customer_id]
      return unless create_stripe_customer

      customer.update!(payment_provider: 'stripe')

      create_result = PaymentProviderCustomers::CreateService.new(customer).create_or_update(
        customer_class: PaymentProviderCustomers::StripeCustomer,
        payment_provider_id: customer.organization.stripe_payment_provider&.id,
        params: billing_configuration,
      )
      create_result.throw_error unless create_result.success?
    end

    def handle_api_billing_configuration(customer, params, new_customer)
      unless params.key?(:billing_configuration)
        create_billing_configuration(customer) if new_customer
        return
      end

      billing_configuration = params[:billing_configuration]

      unless billing_configuration[:payment_provider] == 'stripe'
        customer.update!(payment_provider: nil)
        return
      end

      customer.update!(payment_provider: 'stripe')
      create_or_update_provider_customer(customer, billing_configuration)
    end

    def create_or_update_provider_customer(customer, billing_configuration = {})
      create_result = PaymentProviderCustomers::CreateService.new(customer).create_or_update(
        customer_class: PaymentProviderCustomers::StripeCustomer,
        payment_provider_id: customer.organization.stripe_payment_provider&.id,
        params: billing_configuration,
        async: !(billing_configuration || {})[:sync],
      )
      create_result.throw_error unless create_result.success?
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
