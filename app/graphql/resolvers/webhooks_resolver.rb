# frozen_string_literal: true

module Resolvers
  class WebhooksResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    description 'Query Webhooks'

    argument :page, Integer, required: false
    argument :limit, Integer, required: false
    argument :status, Types::Webhooks::StatusEnum, required: false

    type Types::Webhooks::Object.collection_type, null: false

    def resolve(page: nil, limit: nil, status: nil)
      validate_organization!

      webhooks = current_organization.webhooks
        .page(page)
        .per(limit)

      webhooks = webhooks.where(status:) if status.present?

      webhooks.order(updated_at: :desc)
    end
  end
end
