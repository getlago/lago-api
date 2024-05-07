# frozen_string_literal: true

class AddCreditAmountToInvoices < ActiveRecord::Migration[7.0]
  def up
    change_table :invoices, bulk: true do |t|
      t.bigint :credit_amount_cents, null: false, default: 0
      t.string :credit_amount_currency
    end

    currency_list = WalletTransaction.joins(:wallet).pluck('DISTINCT(wallets.currency)')
    currency_list << 'EUR' if currency_list.blank?
    currency_sql = currency_list.each_with_object([]) do |code, currencies|
      currency = Money::Currency.new(code)
      currencies << "('#{code}', #{currency.exponent}, #{currency.subunit_to_unit})"
    end

    execute <<-SQL
      WITH invoice_credit_amounts AS (
        SELECT
          invoices.id AS invoice_id,
          COALESCE(credit_amounts.credit_sum, 0) AS credit_amount_cents,
          COALESCE(prepaid_amounts.prepaid_sum, 0) AS prepaid_credit_amount_cents
        FROM invoices
          LEFT JOIN (
            SELECT
              credits.invoice_id,
              SUM(credits.amount_cents) AS credit_sum
            FROM credits
            GROUP BY credits.invoice_id
          ) credit_amounts ON credit_amounts.invoice_id = invoices.id
          LEFT JOIN (
            SELECT
              wallet_transactions.invoice_id,
              (ROUND(SUM(wallet_transactions.amount), currencies.exponent) * currencies.subunit_to_unit) AS prepaid_sum
            FROM wallet_transactions
              INNER JOIN wallets ON wallet_transactions.wallet_id = wallets.id
              INNER JOIN (
                SELECT *
                FROM (VALUES #{currency_sql.join(", ")}) AS t(currency, exponent, subunit_to_unit)
              ) currencies ON currencies.currency = wallets.currency
            GROUP BY wallet_transactions.invoice_id, currencies.currency, currencies.exponent, currencies.subunit_to_unit
          ) AS prepaid_amounts ON prepaid_amounts.invoice_id = invoices.id
      )

      UPDATE invoices
      SET
        credit_amount_currency = invoices.amount_currency,
        credit_amount_cents = invoice_credit_amounts.credit_amount_cents + invoice_credit_amounts.prepaid_credit_amount_cents
      FROM invoice_credit_amounts
      WHERE invoice_credit_amounts.invoice_id = invoices.id
    SQL
  end

  def down
    change_table :invoices, bulk: true do |t|
      t.remove :credit_amount_cents
      t.remove :credit_amount_currency
    end
  end
end
