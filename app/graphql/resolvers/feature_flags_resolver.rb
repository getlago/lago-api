# frozen_string_literal: true

module Resolvers
  class FeatureFlagsResolver < GraphQL::Schema::Resolver
    include AuthenticableApiUser
    include RequiredOrganization

    description 'Feature flags enabled for the current organization'

    type Types::Invites::Object.collection_type, null: false

    def resolve
      FeatureFlag::FEATURES.keys.index_with { |name| FeatureFlag.enabled?(name, actor: current_organization) }
    end
  end
end
