# frozen_string_literal: true

module Resolvers
  class EventsResolver < GraphQL::Schema::Resolver
    include AuthenticableApiUser
    include RequiredOrganization

    description 'Query events of an organization'

    argument :page, Integer, required: false
    argument :limit, Integer, required: false

    type Types::Events::Object.collection_type, null: true

    def resolve(page: nil, limit: nil)
      validate_organization!

      current_organization
        .events
        .order(timestamp: :desc)
        .includes(:customer)
        .joins('LEFT OUTER JOIN billable_metrics ON billable_metrics.code = events.code')
        .where(billable_metrics: { organization_id: current_organization.id })
        .select('events.*, billable_metrics.name as billable_metric_name')
        .page(page)
        .per(limit)
    end
  end
end
