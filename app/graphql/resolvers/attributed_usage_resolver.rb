# frozen_string_literal: true

module Resolvers
  class AttributedUsageResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "attributed_usage:view"

    QUERY_LIMIT_ERRORS = %w[too_many_groups query_timeout memory_limit_exceeded].freeze

    AttributedUsage = Data.define(
      :subscription_id, :external_subscription_id, :group_by, :basis, :currency, :from_datetime, :to_datetime,
      :rows, :unattributed, :totals, :metadata
    )

    description "Query the attributed usage of one tree level of an active subscription"

    argument :filters, [Types::AttributedUsage::FilterInput], required: false
    argument :group_by, String, required: true, description: "Code of the usage attribution type to list"
    argument :subscription_id, ID, required: true

    argument :from_datetime, GraphQL::Types::ISO8601DateTime, required: false, description: "Defaults to the current billing period"
    argument :to_datetime, GraphQL::Types::ISO8601DateTime, required: false, description: "Defaults to the current billing period"

    argument :basis, Types::AttributedUsage::BasisEnum, required: false
    argument :charge_ids, [ID], required: false, description: "Defaults to every charge of the plan"
    argument :split_charge_id, ID, required: false

    argument :limit, Integer, required: false
    argument :page, Integer, required: false
    argument :search_term, String, required: false

    type Types::AttributedUsage::Object, null: false

    def resolve(subscription_id:, group_by:, filters: [], from_datetime: nil, to_datetime: nil, basis: "units",
      charge_ids: nil, split_charge_id: nil, limit: UsageAttributions::QueryService::DEFAULT_LIMIT, page: 1, search_term: nil)
      subscription = current_organization.subscriptions.active.find_by(id: subscription_id)
      return not_found_error(resource: "subscription") unless subscription
      return validation_error(messages: {page: ["value_is_out_of_range"]}) unless page.positive?

      charges = subscription.plan.charges.where(id: charge_ids).to_a if charge_ids
      split_charge = subscription.plan.charges.find_by(id: split_charge_id) if split_charge_id

      result = UsageAttributions::QueryService.call(
        subscription:,
        group_by:,
        filters: filters.to_h { [it.code, it.values] },
        from_datetime:,
        to_datetime:,
        charges:,
        split_charge:,
        search: search_term,
        basis:,
        limit:,
        offset: (page - 1) * limit
      )
      return query_error(result) if result.failure?

      AttributedUsage.new(
        subscription_id: subscription.id,
        external_subscription_id: subscription.external_id,
        group_by:,
        basis: result.basis,
        currency: result.currency,
        from_datetime: result.from_datetime,
        to_datetime: result.to_datetime,
        rows: result.rows,
        unattributed: result.unattributed,
        totals: result.totals,
        metadata: UsageAttributions::Page.new(current_page: page, limit_value: limit, total_count: result.groups_count)
      )
    end

    private

    def query_error(result)
      if result.error.is_a?(BaseService::ServiceFailure) && QUERY_LIMIT_ERRORS.include?(result.error.code)
        execution_error(error: "Unprocessable Entity", status: 422, code: result.error.code)
      else
        result_error(result)
      end
    end
  end
end
