# frozen_string_literal: true

module Sources
  # Batches the subscription based counts of plans into one grouped query per count.
  #
  # A plan counts the subscriptions of its kept overrides (child plans) too. The
  # hierarchy is built per requested id, so a parent and one of its overrides can
  # be loaded in the same batch. Customers and draft invoices shared by a plan
  # and its overrides are counted once.
  #
  # Usage in GraphQL types:
  #   dataloader.with(Sources::PlanSubscriptionsCount, :active_subscriptions, object.organization_id).load(object.id)
  class PlanSubscriptionsCount < GraphQL::Dataloader::Source
    KINDS = %i[subscriptions active_subscriptions customers draft_invoices].freeze

    HIERARCHY_JOIN = <<~SQL
      INNER JOIN (
        SELECT id AS root_plan_id, id AS plan_id FROM plans WHERE id IN (:plan_ids)
        UNION ALL
        SELECT parent_id AS root_plan_id, id AS plan_id FROM plans WHERE parent_id IN (:plan_ids) AND deleted_at IS NULL
      ) plan_hierarchy ON plan_hierarchy.plan_id = subscriptions.plan_id
    SQL

    def initialize(kind, organization_id)
      raise ArgumentError, "unknown kind: #{kind}" unless KINDS.include?(kind)

      @kind = kind
      @organization_id = organization_id
    end

    def fetch(plan_ids)
      scope = Subscription
        .joins(Subscription.sanitize_sql([HIERARCHY_JOIN, {plan_ids:}]))
        .group("plan_hierarchy.root_plan_id")

      counts = case @kind
      when :subscriptions
        scope.count
      when :active_subscriptions
        scope.active.count
      when :customers
        scope.active.distinct.count(:customer_id)
      when :draft_invoices
        # The organization filter lets PostgreSQL use the invoices organization index.
        scope.joins(:invoices)
          .merge(Invoice.draft.where(organization_id: @organization_id))
          .distinct
          .count("invoices.id")
      end

      plan_ids.map { counts.fetch(it, 0) }
    end
  end
end
