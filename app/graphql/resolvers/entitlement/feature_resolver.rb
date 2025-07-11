# frozen_string_literal: true

module Resolvers
  module Entitlement
    class FeatureResolver < Resolvers::BaseResolver
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "features:view"

      description "Query a single feature"

      argument :id, ID, required: true, description: "Unique ID of the feature"

      type Types::Entitlement::FeatureObject, null: false

      def resolve(id:)
        raise forbidden_error(code: "feature_unavailable") unless License.premium?

        current_organization.features.find(id)
      rescue ActiveRecord::RecordNotFound
        not_found_error(resource: "feature")
      end
    end
  end
end
