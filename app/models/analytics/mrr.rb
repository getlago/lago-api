# frozen_string_literal: true

module Analytics
  class Mrr < Base
    self.abstract_class = true

    class << self
      def query(organization_id, **args)
        if args[:months].present?
          months_interval = (args[:months].to_i <= 1) ? 0 : args[:months].to_i - 1

          and_months_sql = sanitize_sql(
            [
              "AND am.month >= DATE_TRUNC('month', CURRENT_DATE - INTERVAL ':months months')",
              { months: months_interval },
            ],
          )
        end

        if args[:currency].present?
          and_currency_sql = sanitize_sql(['AND cm.currency = :currency', args[:currency].upcase])
        end

        sql = <<~SQL.squish
          WITH organization_creation_date AS (
            SELECT
              DATE_TRUNC('month', o.created_at) AS start_month
            FROM organizations o
            WHERE o.id = :organization_id
          ),
          all_months AS (
            SELECT
              generate_series(
                  (SELECT start_month FROM organization_creation_date),
                  DATE_TRUNC('month', CURRENT_DATE + INTERVAL '10 years'),
                  interval '1 month'
              ) AS month
          ),
          invoice_details AS (
            SELECT
              f.invoice_id,
              (f.amount_cents + f.taxes_amount_cents)::numeric AS amount_cents,
              f.amount_currency AS currency,
              i.issuing_date,
              p.pay_in_advance,
              CASE
                  WHEN p.interval = 0 THEN 'weekly'
                  WHEN p.interval = 1 THEN 'monthly'
                  WHEN p.interval = 2 THEN 'yearly'
                  WHEN p.interval = 3 THEN 'quarterly'
              END AS plan_interval
            FROM fees f
            LEFT JOIN subscriptions s ON s.id = f.subscription_id
            LEFT JOIN invoice_subscriptions isub ON isub.subscription_id = s.id
            LEFT JOIN invoices i ON i.id = isub.invoice_id
            LEFT JOIN customers c ON c.id = s.customer_id
            LEFT JOIN plans p ON p.id = s.plan_id
            WHERE fee_type = 2
            AND c.organization_id = :organization_id
            AND i.status = 1
          ),
          quarterly_advance AS (
            SELECT
              DATE_TRUNC('month', issuing_date) + interval '1 month' * generate_series(0, 2) AS month,
              amount_cents / 3 AS amount_cents,
              currency
            FROM invoice_details
            WHERE pay_in_advance = TRUE
            AND plan_interval = 'quarterly'
          ),
          quarterly_arrears AS (
            SELECT
              DATE_TRUNC('month', issuing_date) - interval '1 month' * generate_series(2, 0, -1) AS month,
              amount_cents / 3 AS amount_cents,
              currency
            FROM invoice_details
            WHERE pay_in_advance = FALSE
            AND plan_interval = 'quarterly'
          ),
          yearly_advance AS (
            SELECT
              DATE_TRUNC('month', issuing_date) + interval '1 month' * generate_series(0, 11) AS month,
              amount_cents / 12 AS amount_cents,
              currency
            FROM invoice_details
            WHERE pay_in_advance = TRUE
            AND plan_interval = 'yearly'
          ),
          yearly_arrears AS (
            SELECT
              DATE_TRUNC('month', issuing_date) - interval '1 month' * generate_series(11, 0, -1) AS month,
              amount_cents / 12 AS amount_cents,
              currency
            FROM invoice_details
            WHERE pay_in_advance = FALSE
            AND plan_interval = 'yearly'
          ),
          monthly AS (
            SELECT
              DATE_TRUNC('month', issuing_date) - interval '1 month' * generate_series(0, 0, -1) AS month,
              amount_cents,
              currency
            FROM invoice_details
            WHERE plan_interval = 'monthly'
          ),
          weekly AS (
            SELECT
              DATE_TRUNC('month', issuing_date) - interval '1 month' * generate_series(0, 0, -1) AS month,
              currency,
              (SUM(amount_cents) / COUNT(*)) * 4.33 AS amount_cents
            FROM invoice_details
            WHERE plan_interval = 'weekly'
            GROUP BY month, currency
          ),
          consolidated_mrr AS (
            SELECT month, amount_cents::numeric, currency
            FROM quarterly_arrears
            UNION ALL
            SELECT month, amount_cents::numeric, currency
            FROM quarterly_advance
            UNION ALL
            SELECT month, amount_cents::numeric, currency
            FROM yearly_arrears
            UNION ALL
            SELECT month, amount_cents::numeric, currency
            FROM yearly_advance
            UNION ALL
            SELECT month, amount_cents::numeric, currency
            FROM monthly
            UNION ALL
            SELECT month, amount_cents::numeric, currency
            FROM weekly
          )
          SELECT
            am.month,
            cm.currency,
            SUM(cm.amount_cents) AS amount_cents
          FROM all_months am
          LEFT JOIN consolidated_mrr cm ON cm.month = am.month
          WHERE am.month <= DATE_TRUNC('month', CURRENT_DATE)
          #{and_months_sql}
          #{and_currency_sql}
          GROUP BY am.month, cm.currency
          ORDER BY am.month ASC
        SQL

        sanitize_sql([sql, { organization_id: }.merge(args)])
      end

      def cache_key(organization_id, **args)
        [
          'mrr',
          Date.current.strftime('%Y-%m-%d'),
          organization_id,
          args[:currency],
          args[:months],
        ].join('/')
      end
    end
  end
end
