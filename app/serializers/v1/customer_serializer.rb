# frozen_string_literal: true

module V1
  class CustomerSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        external_id: model.external_id,
        name: model.name,
        sequential_id: model.sequential_id,
        slug: model.slug,
        vat_rate: model.vat_rate,
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
        billing_configuration: billing_configuration,
      }
    end

    private

    def billing_configuration
      configuration = {
        payment_provider: model.payment_provider,
      }

      if model.payment_provider&.to_sym == :stripe
        configuration[:provider_customer_id] = model.stripe_customer&.provider_customer_id
        configuration.merge!(model.stripe_customer&.settings || {})
      end

      configuration
    end
  end
end
