# frozen_string_literal: true

module Resolvers
  module Analytics
    class GrossRevenuesResolver < GraphQL::Schema::Resolver
      include AuthenticableApiUser
      include RequiredOrganization

      description 'Query add-ons of an organization'

      argument :ids, [ID], required: false, description: 'List of add-ons IDs to fetch'
      argument :limit, Integer, required: false
      argument :page, Integer, required: false
      argument :search_term, String, required: false

      type Types::Analytics::GrossRevenues::Object.collection_type, null: false

      def resolve(**args)
        validate_organization!

        ::Analytics::GrossRevenue.find_all_by(current_organization.id, **args)
      end
    end
  end
end
