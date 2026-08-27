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
          product_category_id:
        },
        pagination: {
          page:,
          limit:
        }
      )

      return result.plans unless counts_requested?(lookahead)

      preload_counts(result.plans)
    end

    private

    def counts_requested?(lookahead)
      collection = lookahead.selection(:collection)
      COUNT_FIELDS.any? { |field| collection.selects?(field) }
    end

    def preload_counts(plans)
      counts = Plan::CountsQuery.call(
        organization: current_organization,
        filters: {
          plan_ids: plans.map(&:id)
        }
      ).plans

      plans.each do |plan|
        plan_counts = counts.fetch(plan.id, {})
        plan.active_subscriptions_count = plan_counts.fetch(:active_subscriptions_count, 0)
        plan.charges_count = plan_counts.fetch(:charges_count, 0)
        plan.customers_count = plan_counts.fetch(:customers_count, 0)
        plan.draft_invoices_count = plan_counts.fetch(:draft_invoices_count, 0)
        plan.fixed_charges_count = plan_counts.fetch(:fixed_charges_count, 0)
        plan.subscriptions_count = plan_counts.fetch(:subscriptions_count, 0)
      end

      plans
    end
  end
end
