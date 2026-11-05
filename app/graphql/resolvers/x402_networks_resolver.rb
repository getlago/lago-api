# frozen_string_literal: true

module Resolvers
  class X402NetworksResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "organization:integrations:view"

    description "Query the networks an x402 connection can accept payments on"

    type [Types::X402::Network], null: false

    def resolve
      raise forbidden_error(code: "feature_unavailable") unless current_organization.x402_payments_enabled?

      ::X402::Network::NETWORKS.map do |id, environment|
        {
          id:,
          name: ::X402::Network::NAMES.fetch(id),
          family: ::X402::Network.family_of_network(id).to_s,
          environment: environment.to_s
        }
      end
    end
  end
end
