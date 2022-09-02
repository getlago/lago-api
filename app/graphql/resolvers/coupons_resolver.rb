# frozen_string_literal

module Resolvers
  class CouponsResolver < GraphQL::Schema::Resolver
    include AuthenticableApiUser
    include RequiredOrganization

    description 'Query coupons of an organization'

    argument :ids, [ID], required: false, description: 'List of coupon IDs to fetch'
    argument :page, Integer, required: false
    argument :limit, Integer, required: false
    argument :status, Types::Coupons::StatusEnum, required: false

    type Types::Coupons::Object.collection_type, null: false

    def resolve(ids: nil, page: nil, limit: nil, status: nil)
      validate_organization!

      coupons = current_organization
        .coupons
        .order_by_status_and_expiration
        .page(page)
        .per(limit)

      coupons = coupons.where(status: status) if status.present?
      coupons = coupons.where(id: ids) if ids.present?

      coupons
    end
  end
end
