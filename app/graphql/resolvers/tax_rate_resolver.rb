# frozen_string_literal: true

module Resolvers
  class TaxRateResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    description 'Query a single tax rate of an organization'

    argument :id, ID, required: true, description: 'Uniq ID of the tax rate'

    type Types::TaxRates::Object, null: true

    def resolve(id: nil)
      validate_organization!

      current_organization.tax_rates.find(id)
    rescue ActiveRecord::RecordNotFound
      not_found_error(resource: 'tax_rate')
    end
  end
end
