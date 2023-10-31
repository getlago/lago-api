# frozen_string_literal: true

module Metrics
  class GrossRevenue < Base
    self.abstract_class = true

    class << self
      def columns
        Struct.new(:month, :amount_cents, :currency)
      end

      def query(organization_id, **args)
        if args[:customer_external_id].present?
          and_customer_external_id_sql = sanitize_sql(
            ['AND c.external_id = :customer_external_id', args[:customer_external_id]],
          )
        end

        if args[:currency].present?
          and_currency_sql = sanitize_sql(['AND cd.currency = :currency', args[:currency].upcase])
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
                i.issuing_date,
                i.total_amount_cents::float AS amount_cents,
                i.currency
            FROM invoices i
            LEFT JOIN customers c ON i.customer_id = c.id
            WHERE i.organization_id = :organization_id
                AND i.status = 1
                #{and_customer_external_id_sql}
          ),
          instant_charges AS (
            SELECT
                f.created_at AS issuing_date,
                f.amount_cents AS amount_cents,
                f.amount_currency AS currency
            FROM fees f
            LEFT JOIN subscriptions s ON f.subscription_id = s.id
            LEFT JOIN customers c ON c.id = s.customer_id
            WHERE c.organization_id = :organization_id
                AND f.invoice_id IS NULL
                AND f.pay_in_advance IS TRUE
                #{and_customer_external_id_sql}
          ),
          combined_data AS (
            SELECT
                DATE_TRUNC('month', issuing_date) AS month,
                currency,
                COALESCE(SUM(amount_cents), 0) AS amount_cents
            FROM (
                SELECT * FROM issued_invoices
                UNION ALL
                SELECT * FROM instant_charges
            ) AS gross_revenue
            GROUP BY month, currency
          )
          SELECT
            am.month,
            cd.amount_cents,
            cd.currency
          FROM all_months am
          LEFT JOIN combined_data cd ON am.month = cd.month
          WHERE am.month <= DATE_TRUNC('month', CURRENT_DATE)
          #{and_currency_sql}
          ORDER BY am.month;
        SQL

        sanitize_sql([sql, { organization_id: }.merge(args)])
      end
    end
  end
end
