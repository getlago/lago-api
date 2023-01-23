# frozen_string_literal: true

module V1
  class BillableMetricSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        name: model.name,
        code: model.code,
        description: model.description,
        aggregation_type: model.aggregation_type,
        created_at: model.created_at.iso8601,
        field_name: model.field_name,
        group: model.active_groups_as_tree,
        active_subscriptions_count:,
        draft_invoices_count:,
      }
    end

    private

    def active_subscriptions_count
      model.plans.joins(:subscriptions).merge(Subscription.active).count
    end

    def draft_invoices_count
      model.charges
        .joins(fees: [:invoice])
        .merge(Invoice.draft)
        .select(:invoice_id)
        .distinct
        .count
    end
  end
end
