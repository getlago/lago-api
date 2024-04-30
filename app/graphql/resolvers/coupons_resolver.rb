# frozen_string_literal: true

module Resolvers
  class CouponsResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = 'coupons:view'

    description 'Query coupons of an organization'

    argument :ids, [ID], required: false, description: 'List of coupon IDs to fetch'
    argument :limit, Integer, required: false
    argument :page, Integer, required: false
    argument :search_term, String, required: false
    argument :status, Types::Coupons::StatusEnum, required: false

    type Types::Coupons::Object.collection_type, null: false

    def resolve(ids: nil, page: nil, limit: nil, status: nil, search_term: nil)
      query = CouponsQuery.new(organization: current_organization)
      result = query.call(
        search_term:,
        page:,
        limit:,
        status:,
        filters: {
          ids:,
        },
      )

      result.coupons
    end
  end
end
