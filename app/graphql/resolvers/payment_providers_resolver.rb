# frozen_string_literal: true

module Resolvers
  class PaymentProvidersResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = 'organization:integrations:view'

    description "Query organization's payment providers"

    argument :limit, Integer, required: false
    argument :page, Integer, required: false
    argument :type, Types::PaymentProviders::ProviderTypeEnum, required: false

    type Types::PaymentProviders::Object.collection_type, null: true

    def resolve(type: nil, page: nil, limit: nil)
      scope = current_organization.payment_providers.page(page).per(limit)
      scope = scope.where(type: provider_type(type)) if type.present?
      scope
    end

    private

    def provider_type(type)
      case type
      when 'adyen'
        'PaymentProviders::AdyenProvider'
      when 'stripe'
        'PaymentProviders::StripeProvider'
      when 'gocardless'
        'PaymentProviders::GocardlessProvider'
      else
        raise(NotImplementedError)
      end
    end
  end
end
