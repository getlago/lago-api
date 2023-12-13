# frozen_string_literal: true

module Resolvers
  class PaymentProviderResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    description 'Query a single payment provider'

    argument :id, ID, required: true, description: 'Uniq ID of the payment provider'

    type Types::PaymentProviders::Object, null: true

    def resolve(id:)
      validate_organization!

      current_organization.payment_providers.find(id)
    rescue ActiveRecord::RecordNotFound
      not_found_error(resource: 'payment_provider')
    end
  end
end
