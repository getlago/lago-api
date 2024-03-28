# frozen_string_literal: true

module Analytics
  class InvoiceCollection < Base
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
          and_currency_sql = sanitize_sql(['AND currency = :currency', args[:currency].upcase])
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
          invoices_per_status AS (
            SELECT
                DATE_TRUNC('month', i.issuing_date) AS month,
                i.currency,
                CASE
                    WHEN i.payment_status = 0 THEN 'pending'
                    WHEN i.payment_status = 1 THEN 'succeeded'
                    WHEN i.payment_status = 2 THEN 'failed'
                END AS payment_status,
                COALESCE(COUNT(*), 0) AS invoices_count,
                COALESCE(SUM(i.total_amount_cents::float), 0) AS amount_cents
            FROM invoices i
            WHERE i.organization_id = :organization_id
            AND i.status = 1
            AND i.payment_dispute_lost_at IS NULL
            GROUP BY payment_status, month, currency
          )
          SELECT
            am.month,
            payment_status,
            currency,
            COALESCE(invoices_count, 0) AS invoices_count,
            COALESCE(amount_cents, 0) AS amount_cents
          FROM all_months am
          LEFT JOIN invoices_per_status ips ON ips.month = am.month AND ips.payment_status IS NOT NULL
          WHERE am.month <= DATE_TRUNC('month', CURRENT_DATE)
          #{and_months_sql}
          #{and_currency_sql}
          ORDER BY am.month, payment_status, currency;
        SQL

        sanitize_sql([sql, { organization_id: }.merge(args)])
      end

      def cache_key(organization_id, **args)
        [
          'invoice-collection',
          Date.current.strftime('%Y-%m-%d'),
          organization_id,
          args[:currency],
          args[:months],
        ].join('/')
      end
    end
  end
end
