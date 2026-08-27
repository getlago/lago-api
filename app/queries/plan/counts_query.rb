# frozen_string_literal: true

class Plan
  class CountsQuery < BaseQuery
    Result = BaseResult[:plans]
    Filters = BaseFilters[:plan_ids]

    def call
      query_result = ActiveRecord::Base.connection.exec_query(counts_query)

      result.plans = query_result.each_with_object({}) do |row, hash|
        hash[row["plan_id"]] = {
          active_subscriptions_count: row["active_subscriptions_count"],
          charges_count: row["charges_count"],
          customers_count: row["customers_count"],
          draft_invoices_count: row["draft_invoices_count"],
          fixed_charges_count: row["fixed_charges_count"],
          subscriptions_count: row["subscriptions_count"]
        }
      end

      result
    end

    private

    def counts_query
      ActiveRecord::Base.sanitize_sql_array([
        counts_sql,
        filters.plan_ids,
        organization.id,
        Subscription.statuses[:active],
        Invoice.statuses[:draft]
      ])
    end

    def counts_sql
      <<~SQL
        WITH
          selected_plans AS (
            SELECT
              id
            FROM
              plans
            WHERE
              id IN (?)
              AND organization_id = ?
          ),
          plan_hierarchy AS (
            SELECT
              id AS root_plan_id,
              id AS plan_id,
              TRUE AS direct
            FROM
              selected_plans
            UNION ALL
            SELECT
              selected_plans.id AS root_plan_id,
              children.id AS plan_id,
              FALSE AS direct
            FROM
              selected_plans
              INNER JOIN plans AS children ON children.parent_id = selected_plans.id
            WHERE
              children.deleted_at IS NULL
          ),
          subscription_counts AS (
            SELECT
              plan_hierarchy.root_plan_id AS plan_id,
              COUNT(subscriptions.id) AS subscriptions_count
            FROM
              plan_hierarchy
              INNER JOIN subscriptions ON subscriptions.plan_id = plan_hierarchy.plan_id
            GROUP BY
              plan_hierarchy.root_plan_id
          ),
          active_subscription_counts AS (
            SELECT
              plan_hierarchy.root_plan_id AS plan_id,
              COUNT(subscriptions.id) AS active_subscriptions_count,
              COUNT(DISTINCT subscriptions.customer_id) FILTER (WHERE plan_hierarchy.direct)
                + COUNT(DISTINCT subscriptions.customer_id) FILTER (WHERE NOT plan_hierarchy.direct)
                AS customers_count
            FROM
              plan_hierarchy
              INNER JOIN subscriptions ON subscriptions.plan_id = plan_hierarchy.plan_id
            WHERE
              subscriptions.status = ?
            GROUP BY
              plan_hierarchy.root_plan_id
          ),
          draft_invoice_counts AS (
            SELECT
              plan_hierarchy.root_plan_id AS plan_id,
              COUNT(DISTINCT invoices.id) FILTER (WHERE plan_hierarchy.direct)
                + COUNT(DISTINCT invoices.id) FILTER (WHERE NOT plan_hierarchy.direct)
                AS draft_invoices_count
            FROM
              plan_hierarchy
              INNER JOIN subscriptions ON subscriptions.plan_id = plan_hierarchy.plan_id
              INNER JOIN invoice_subscriptions ON invoice_subscriptions.subscription_id = subscriptions.id
              INNER JOIN invoices ON invoices.id = invoice_subscriptions.invoice_id
            WHERE
              invoices.status = ?
            GROUP BY
              plan_hierarchy.root_plan_id
          ),
          charge_counts AS (
            SELECT
              selected_plans.id AS plan_id,
              COUNT(charges.id) AS charges_count
            FROM
              selected_plans
              INNER JOIN charges ON charges.plan_id = selected_plans.id
            WHERE
              charges.deleted_at IS NULL
            GROUP BY
              selected_plans.id
          ),
          fixed_charge_counts AS (
            SELECT
              selected_plans.id AS plan_id,
              COUNT(fixed_charges.id) AS fixed_charges_count
            FROM
              selected_plans
              INNER JOIN fixed_charges ON fixed_charges.plan_id = selected_plans.id
            WHERE
              fixed_charges.deleted_at IS NULL
            GROUP BY
              selected_plans.id
          )
        SELECT
          selected_plans.id AS plan_id,
          COALESCE(active_subscription_counts.active_subscriptions_count, 0) AS active_subscriptions_count,
          COALESCE(charge_counts.charges_count, 0) AS charges_count,
          COALESCE(active_subscription_counts.customers_count, 0) AS customers_count,
          COALESCE(draft_invoice_counts.draft_invoices_count, 0) AS draft_invoices_count,
          COALESCE(fixed_charge_counts.fixed_charges_count, 0) AS fixed_charges_count,
          COALESCE(subscription_counts.subscriptions_count, 0) AS subscriptions_count
        FROM
          selected_plans
          LEFT JOIN subscription_counts ON subscription_counts.plan_id = selected_plans.id
          LEFT JOIN active_subscription_counts ON active_subscription_counts.plan_id = selected_plans.id
          LEFT JOIN draft_invoice_counts ON draft_invoice_counts.plan_id = selected_plans.id
          LEFT JOIN charge_counts ON charge_counts.plan_id = selected_plans.id
          LEFT JOIN fixed_charge_counts ON fixed_charge_counts.plan_id = selected_plans.id
      SQL
    end
  end
end
