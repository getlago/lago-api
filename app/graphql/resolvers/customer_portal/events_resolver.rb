# frozen_string_literal: true

module Resolvers
  module CustomerPortal
    class EventsResolver < GraphQL::Schema::Resolver
      include AuthenticableCustomerPortalUser
  
      description 'Query events for a customer'
  
      argument :limit, Integer, required: false
      argument :page, Integer, required: false
  
      type Types::Events::Object.collection_type, null: true
  
      def resolve(page: nil, limit: nil)

        current_organizaton = context[:customer_portal_user].organization
        current_customer = context[:customer_portal_user].id

        current_organizaton.events
          .order(timestamp: :desc)
          .includes(:customer)
          .joins('LEFT OUTER JOIN billable_metrics ON billable_metrics.code = events.code')
          .where(billable_metrics: { deleted_at: nil })
          .where(
            events: { customer_id: current_customer }
          )
          .select(
            [
              'events.*',
              'billable_metrics.name as billable_metric_name',
              'billable_metrics.field_name as billable_metric_field_name',
            ].join(','),
          )
          .page(page)
          .per(limit)
      end
    end
  end
end
