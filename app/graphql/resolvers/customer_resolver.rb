# frozen_string_literal: true

module Resolvers
  class CustomerResolver < GraphQL::Schema::Resolver
    include AuthenticableApiUser
    include RequiredOrganization

    description 'Query a single customer of an organization'

    argument :id, ID, required: true, description: 'Uniq ID of the customer'

    type Types::Customers::SingleObject, null: true

    def resolve(id: nil)
      validate_organization!

      current_organization.customers.find_by(id: id)
    end
  end
end
