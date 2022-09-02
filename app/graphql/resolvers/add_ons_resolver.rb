# frozen_string_literal

module Resolvers
  class AddOnsResolver < GraphQL::Schema::Resolver
    include AuthenticableApiUser
    include RequiredOrganization

    description 'Query add-ons of an organization'

    argument :ids, [ID], required: false, description: 'List of add-ons IDs to fetch'
    argument :page, Integer, required: false
    argument :limit, Integer, required: false

    type Types::AddOns::Object.collection_type, null: false

    def resolve(ids: nil, page: nil, limit: nil)
      validate_organization!

      add_ons = current_organization
        .add_ons
        .order(created_at: :desc)
        .page(page)
        .per(limit)

      add_ons = add_ons.where(id: ids) if ids.present?

      add_ons
    end
  end
end
