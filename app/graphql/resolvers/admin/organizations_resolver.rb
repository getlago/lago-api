# frozen_string_literal: true

module Resolvers
  module Admin
    class OrganizationsResolver < Resolvers::BaseResolver
      include AuthenticableStaffUser

      description "List or search organizations across all tenants (Lago staff only)"

      argument :search_term, String, required: false
      argument :page, Integer, required: false
      argument :limit, Integer, required: false

      type Types::Admin::OrganizationType.collection_type, null: false

      def resolve(search_term: nil, page: nil, limit: nil)
        scope = ::Organization.order(created_at: :desc)

        if search_term.present?
          term = search_term.to_s.strip
          if uuid?(term)
            scope = scope.where(id: term)
          else
            like = "%#{term.downcase}%"
            scope = scope.where("LOWER(name) LIKE ? OR LOWER(email) LIKE ?", like, like)
          end
        end

        scope.page(page || 1).per((limit || 25).clamp(1, 100))
      end

      private

      def uuid?(value)
        value.to_s.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
      end
    end
  end
end
