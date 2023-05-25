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
        timezone: model.timezone,
        applicable_timezone: model.applicable_timezone,
        billing_configuration:,
      }

      payload = payload.merge(metadata) if include?(:metadata)

      payload
    end

    private

    def metadata
      ::CollectionSerializer.new(
        model.metadata,
        ::V1::Customers::MetadataSerializer,
        collection_name: 'metadata',
      ).serialize
    end

    def billing_configuration
      configuration = {
        invoice_grace_period: model.invoice_grace_period,
        payment_provider: model.payment_provider,
        vat_rate: model.vat_rate,
        document_locale: model.document_locale,
      }

      if model.payment_provider&.to_sym == :stripe
        configuration[:provider_customer_id] = model.stripe_customer&.provider_customer_id
        configuration.merge!(model.stripe_customer&.settings || {})
      elsif model.payment_provider&.to_sym == :gocardless
        configuration[:provider_customer_id] = model.gocardless_customer&.provider_customer_id
        configuration.merge!(model.gocardless_customer&.settings || {})
      elsif model.payment_provider&.to_sym == :adyen
        configuration[:provider_customer_id] = model.adyen_customer&.provider_customer_id
        configuration.merge!(model.adyen_customer&.settings || {})
      end

      configuration
    end
  end
end
