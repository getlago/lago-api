# frozen_string_literal: true

module Analytics
  class GrossRevenue < Base
    self.abstract_class = true

    class << self
      def query(organization_id, **args)
        if args[:external_customer_id].present?
          and_external_customer_id_sql = sanitize_sql(
            ['AND c.external_id = :external_customer_id', args[:external_customer_id]],
          )
        end

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
          and_currency_sql = sanitize_sql(['AND cd.currency = :currency', args[:currency].upcase])
          select_currency_sql = sanitize_sql(['COALESCE(cd.currency, :currency) as currency', args[:currency].upcase])
        else
          select_currency_sql = 'cd.currency'
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
          issued_invoices AS (
            SELECT
              i.id,
              i.issuing_date,
              i.total_amount_cents::float AS amount_cents,
              i.currency,
              COALESCE(SUM(refund_amount_cents::float),0) AS total_refund_amount_cents
            FROM invoices i
            LEFT JOIN customers c ON i.customer_id = c.id
            LEFT JOIN credit_notes cn ON cn.invoice_id = i.id
            WHERE i.organization_id = :organization_id
            AND i.status = 1
            #{and_external_customer_id_sql}
            GROUP BY i.id, i.issuing_date, i.total_amount_cents, i.currency
            ORDER BY i.issuing_date ASC
          ),
          instant_charges AS (
            SELECT
              f.id,
              f.created_at AS issuing_date,
              f.amount_cents AS amount_cents,
              f.amount_currency AS currency,
              0 AS total_refund_amount_cents
            FROM fees f
            LEFT JOIN subscriptions s ON f.subscription_id = s.id
            LEFT JOIN customers c ON c.id = s.customer_id
            WHERE c.organization_id = :organization_id
            AND f.invoice_id IS NULL
            AND f.pay_in_advance IS TRUE
            #{and_external_customer_id_sql}
          ),
          combined_data AS (
            SELECT
              DATE_TRUNC('month', issuing_date) AS month,
              currency,
              COALESCE(SUM(amount_cents), 0) AS amount_cents,
              COALESCE(SUM(total_refund_amount_cents), 0) AS total_refund_amount_cents
            FROM (
              SELECT * FROM issued_invoices
              UNION ALL
              SELECT * FROM instant_charges
            ) AS gross_revenue
            GROUP BY month, currency, total_refund_amount_cents
          )
          SELECT
            am.month,
            #{select_currency_sql},
            SUM(cd.amount_cents - cd.total_refund_amount_cents) AS amount_cents
          FROM all_months am
          LEFT JOIN combined_data cd ON am.month = cd.month
          WHERE am.month <= DATE_TRUNC('month', CURRENT_DATE)
          #{and_months_sql}
          #{and_currency_sql}
          AND cd.amount_cents IS NOT NULL
          GROUP BY am.month, cd.currency
          ORDER BY am.month;
        SQL

        sanitize_sql([sql, { organization_id: }.merge(args)])
      end

      def cache_key(organization_id, **args)
        [
          'gross-revenue',
          Date.current.strftime('%Y-%m-%d'),
          organization_id,
          args[:external_customer_id],
          args[:currency],
          args[:months],
        ].join('/')
      end
    end
  end
end
