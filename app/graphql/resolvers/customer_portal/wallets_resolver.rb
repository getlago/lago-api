# frozen_string_literal: true

module Resolvers
  module CustomerPortal
    class WalletsResolver < Resolvers::BaseResolver
      include AuthenticableCustomerPortalUser

      description 'Query wallets'

      argument :limit, Integer, required: false
      argument :page, Integer, required: false

      type Types::CustomerPortal::Wallets::Object.collection_type, null: false

      def resolve(page: nil, limit: nil)
        context[:customer_portal_user]
          .wallets
          .active
          .page(page)
          .per(limit)
          .order(created_at: :desc)
      rescue ActiveRecord::RecordNotFound
        not_found_error(resource: 'customer')
      end
    end
  end
end
