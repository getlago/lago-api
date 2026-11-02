# frozen_string_literal: true

module V2
  class CustomerSerializer < ModelSerializer
    timestamps :created_at, :updated_at, :deleted_at

    expandable :metadata, serializer: ::V2::Customers::MetadataSerializer
    expandable :taxes, serializer: ::V2::TaxSerializer
    expandable :integration_customers, serializer: ::V1::IntegrationCustomerSerializer

    def serialize
      payload = {
        lago_id: model.id,
        billing_entity_code: model.billing_entity.code,
        external_id: model.external_id,
        account_type: model.account_type,
        name: model.name,
        firstname: model.firstname,
        lastname: model.lastname,
        customer_type: model.customer_type,
        sequential_id: model.sequential_id,
        slug: model.slug,
        country: model.country,
        address_line1: model.address_line1,
        address_line2: model.address_line2,
        state: model.state,
        zipcode: model.zipcode,
        email: model.email,
        city: model.city,
        url: model.url,
        phone: model.phone,
        logo_url: model.logo_url,
        legal_name: model.legal_name,
        legal_number: model.legal_number,
        currency: model.currency,
        tax_identification_number: model.tax_identification_number,
        timezone: model.timezone,
        applicable_timezone: model.applicable_timezone,
        external_salesforce_id: model.external_salesforce_id,
        finalize_zero_amount_invoice: model.finalize_zero_amount_invoice,
        skip_invoice_custom_sections: model.skip_invoice_custom_sections,
        **billing_fields,
        **x402_payload
      }

      if options[:include_shipping_address]
        payload[:shipping_address] = model.shipping_address
      end

      payload
    end

    private

    def billing_fields
      provider_customer = model.provider_customer
      {
        invoice_grace_period: model.invoice_grace_period,
        periodic_invoice_issuing_date_anchor: model.subscription_invoice_issuing_date_anchor,
        periodic_invoice_issuing_date_adjustment: model.subscription_invoice_issuing_date_adjustment,
        payment_provider: model.payment_provider,
        payment_provider_code: model.payment_provider_code,
        provider_customer_id: provider_customer&.provider_customer_id,
        provider_payment_methods: provider_customer&.provider_payment_methods,
        document_locale: model.document_locale
      }
    end

    def metadata = model.metadata.order(:created_at, :id)

    def taxes = model.taxes.order(:created_at, :id)

    def integration_customers = model.integration_customers.preload(:integration).order(:created_at, :id)

    # As V1, only for an organization that takes x402 payments.
    def x402_payload
      model.organization.x402_payments_enabled? ? {x402_agent_address: model.x402_agent_address} : {}
    end
  end
end
