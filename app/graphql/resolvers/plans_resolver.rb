# frozen_string_literal: true

module Resolvers
  class PlansResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "plans:view"
    COUNT_FIELDS = %i[
      active_subscriptions_count
      charges_count
      customers_count
      draft_invoices_count
      fixed_charges_count
      subscriptions_count
    ].freeze

    description "Query plans of an organization"

    extras [:lookahead]

    argument :limit, Integer, required: false
    argument :page, Integer, required: false
    argument :product_category_id, ID, required: false
    argument :search_term, String, required: false
    argument :with_deleted, Boolean, required: false

    type Types::Plans::Object.collection_type, null: false

    def resolve(lookahead:, page: nil, limit: nil, search_term: nil, with_deleted: nil, product_category_id: nil)
      result = PlansQuery.call(
        organization: current_organization,
        search_term:,
        filters: {
          with_deleted:,
          product_category_id:,
          preload_counts: counts_requested?(lookahead)
        },
        pagination: {
          page:,
          limit:
        }
      )

      result.plans
    end

    private

    def counts_requested?(lookahead)
      collection = lookahead.selection(:collection)
      COUNT_FIELDS.any? { |field| collection.selects?(field) }
    end
  end
end
