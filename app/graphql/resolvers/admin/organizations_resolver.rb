# frozen_string_literal: true

module Resolvers
  module Admin
    class OrganizationsResolver < Resolvers::BaseResolver
      include AuthenticableAdminUser

      description "Search organizations (admin only)"

      argument :search_term, String, required: false
      argument :page, Integer, required: false
      argument :limit, Integer, required: false

      type Types::Admin::OrganizationType.collection_type, null: false

      def resolve(search_term: nil, page: nil, limit: nil)
        organizations = Organization.all

        if search_term.present?
          organizations = organizations.where(
            "name ILIKE :term OR id::text ILIKE :term",
            term: "%#{search_term}%"
          )
        end

        organizations.order(created_at: :desc).page(page).per(limit || 25)
      end
    end
  end
end
