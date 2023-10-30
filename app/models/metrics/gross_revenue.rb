# frozen_string_literal: true

module Metrics
  class GrossRevenue < Base
    self.abstract_class = true

    class << self
      def columns
        Struct.new(:month, :total_gross_revenue)
      end

      def query
        <<~SQL
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
                DATE_TRUNC('month', i.issuing_date) AS month,
                COALESCE(SUM(i.total_amount_cents::float / 100), 0) AS amount
            FROM invoices i
            WHERE i.organization_id = :organization_id
                AND i.status = 1
            GROUP BY month
          ),
          instant_charges AS (
            SELECT
                DATE_TRUNC('month', f.created_at) AS month,
                COALESCE(SUM(f.amount_cents::float / 100), 0) AS amount
            FROM fees f
            LEFT JOIN subscriptions s ON f.subscription_id = s.id
            LEFT JOIN customers c ON c.id = s.customer_id
            WHERE c.organization_id = :organization_id
                AND f.invoice_id IS NULL
                AND f.pay_in_advance IS TRUE
            GROUP BY month
          ),
          combined_data AS (
            SELECT
                month,
                COALESCE(SUM(amount), 0) AS total_gross_revenue
            FROM (
                SELECT * FROM issued_invoices
                UNION ALL
                SELECT * FROM instant_charges
            ) AS gross_revenue
            GROUP BY month
          )
          SELECT
            am.month,
            ROUND(CAST(COALESCE(cd.total_gross_revenue, 0) AS NUMERIC), 2) AS total_gross_revenue
          FROM all_months am
          LEFT JOIN combined_data cd ON am.month = cd.month
          WHERE am.month <= DATE_TRUNC('month', CURRENT_DATE)
          ORDER BY am.month
        SQL
      end
    end
  end
end
