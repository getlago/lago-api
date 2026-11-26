# frozen_string_literal: true

module Resolvers
  class X402ConnectionsResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "organization:integrations:view"

    description "Query the x402 connections of an organization"

    argument :limit, Integer, required: false
    argument :page, Integer, required: false

    type Types::X402::Connection.collection_type, null: false

    def resolve(page: nil, limit: nil)
      raise forbidden_error(code: "feature_unavailable") unless current_organization.x402_payments_enabled?

      current_organization.x402_connections.order(created_at: :desc).order(id: :asc).page(page).per(limit)
    end
  end
end
