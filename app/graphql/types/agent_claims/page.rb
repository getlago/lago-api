# frozen_string_literal: true

module Types
  module AgentClaims
    class Page < Types::BaseObject
      graphql_name "AgentClaimPage"
      description "The names shown on the public claim page of an agent storefront"

      field :organization_name, String, null: false
      field :storefront_name, String, null: false, method: :name

      def organization_name
        object.organization.name
      end
    end
  end
end
