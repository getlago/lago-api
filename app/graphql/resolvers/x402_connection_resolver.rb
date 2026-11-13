# frozen_string_literal: true

module Resolvers
  class X402ConnectionResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "organization:integrations:view"

    description "Query a single x402 connection"

    argument :id, ID, required: true, description: "Uniq ID of the x402 connection"

    type Types::X402::Connection, null: true

    def resolve(id:)
      raise forbidden_error(code: "feature_unavailable") unless current_organization.x402_payments_enabled?

      current_organization.x402_connections.find(id)
    rescue ActiveRecord::RecordNotFound
      not_found_error(resource: "x402_connection")
    end
  end
end
