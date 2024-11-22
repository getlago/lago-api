# frozen_string_literal: true

module V1
  class BillableMetricSerializer < ModelSerializer
    def serialize
      payload = {
        lago_id: model.id,
        name: model.name,
        code: model.code,
        description: model.description,
        aggregation_type: model.aggregation_type,
        weighted_interval: model.weighted_interval,
        recurring: model.recurring,
        rounding_function: model.rounding_function,
        rounding_precision: model.rounding_precision,
        created_at: model.created_at.iso8601,
        field_name: model.field_name,
        expression: model.expression
      }

      payload.merge!(counters) if include?(:counters)
      payload.merge!(filters)

      payload
    end

    private

    def counters
      {
        active_subscriptions_count:,
        draft_invoices_count:,
        plans_count:
      }
    end

    def active_subscriptions_count
      Subscription.active.where(plan_id: model.charges.select(:plan_id).distinct).count
    end

    def draft_invoices_count
      Invoice.draft.where(id: model.charges
        .joins(:fees)
        .select(:invoice_id)).count
    end

    def plans_count
      model.plans.distinct.count
    end

    def filters
      ::CollectionSerializer.new(
        model.filters,
        ::V1::BillableMetricFilterSerializer,
        collection_name: "filters"
      ).serialize
    end
  end
end
