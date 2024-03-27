# frozen_string_literal: true

module Resolvers
  class CustomerResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    description "Query a single customer of an organization"

    argument :id, ID, required: true, description: "Uniq ID of the customer"

    type Types::Customers::Object, null: true

    def resolve(id: nil)
      validate_organization!

      current_organization.customers.find(id)
    rescue ActiveRecord::RecordNotFound
      not_found_error(resource: "customer")
    end
  end
end
