# frozen_string_literal: true

module V1
  class CustomerSerializer < ModelSerializer
    def serialize
      payload = {
        lago_id: model.id,
        external_id: model.external_id,
        name: model.name,
        sequential_id: model.sequential_id,
        slug: model.slug,
        created_at: model.created_at.iso8601,
        updated_at: model.updated_at.iso8601,
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
        net_payment_term: model.net_payment_term,
        external_salesforce_id: model.external_salesforce_id,
        billing_configuration:,
        shipping_address: model.shipping_address
      }

      payload = payload.merge(metadata)
      payload = payload.merge(taxes) if include?(:taxes)
      payload = payload.merge(vies_check) if include?(:vies_check)
      payload = payload.merge(integration_customers) if include?(:integration_customers)

      payload
    end

    private

    def metadata
      ::CollectionSerializer.new(
        model.metadata,
        ::V1::Customers::MetadataSerializer,
        collection_name: 'metadata'
      ).serialize
    end

    def billing_configuration
      configuration = {
        invoice_grace_period: model.invoice_grace_period,
        payment_provider: model.payment_provider,
        payment_provider_code: model.payment_provider_code,
        document_locale: model.document_locale
      }

      case model.payment_provider&.to_sym
      when :stripe
        configuration[:provider_customer_id] = model.stripe_customer&.provider_customer_id
        configuration[:provider_payment_methods] = model.stripe_customer&.provider_payment_methods
        configuration.merge!(model.stripe_customer&.settings || {})
      when :gocardless
        configuration[:provider_customer_id] = model.gocardless_customer&.provider_customer_id
        configuration.merge!(model.gocardless_customer&.settings || {})
      when :adyen
        configuration[:provider_customer_id] = model.adyen_customer&.provider_customer_id
        configuration.merge!(model.adyen_customer&.settings || {})
      end

      configuration
    end

    def taxes
      ::CollectionSerializer.new(model.taxes, ::V1::TaxSerializer, collection_name: 'taxes').serialize
    end

    def vies_check
      vies_value = options.fetch(:vies_check)

      {
        vies_check: vies_value.is_a?(Hash) ? vies_value : {valid: false}
      }
    end

    def integration_customers
      ::CollectionSerializer.new(
        model.integration_customers,
        ::V1::IntegrationCustomerSerializer,
        collection_name: 'integration_customers'
      ).serialize
    end
  end
end
