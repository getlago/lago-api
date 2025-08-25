# frozen_string_literal: true

module Resolvers
  module Entitlement
    class FeaturesResolver < Resolvers::BaseResolver
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "features:view"

      description "Query features of an organization"

      argument :limit, Integer, required: false
      argument :page, Integer, required: false
      argument :search_term, String, required: false

      type Types::Entitlement::FeatureObject.collection_type, null: false

      def resolve(**args)
        raise forbidden_error(code: "feature_unavailable") unless License.premium?

        result = ::Entitlement::FeaturesQuery.call(
          organization: current_organization,
          search_term: args[:search_term],
          pagination: {
            page: args[:page],
            limit: args[:limit]
          }
        )

        result.features.includes(:privileges)
      end
    end
  end
end
