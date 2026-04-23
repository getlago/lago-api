# frozen_string_literal: true

module Resolvers
  module Admin
    class OrganizationsResolver < Resolvers::BaseResolver
      include AuthenticableStaffUser

      description "Search organizations across all tenants (Lago staff only)"

      argument :limit, Integer, required: false
      argument :page, Integer, required: false
      argument :search_term, String, required: false

      type Types::Admin::OrganizationType.collection_type, null: false

      def resolve(search_term: nil, page: nil, limit: nil)
        scope = ::Organization.order(created_at: :desc)

        if search_term.present?
          term = "%#{search_term.to_s.strip.downcase}%"
          scope =
            if uuid?(search_term)
              scope.where(id: search_term)
            else
              scope.where("LOWER(name) LIKE ? OR LOWER(email) LIKE ?", term, term)
            end
        end

        scope.page(page || 1).per(limit || 25)
      end

      private

      def uuid?(value)
        value.to_s.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
      end
    end
  end
end
