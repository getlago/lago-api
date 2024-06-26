# frozen_string_literal: true

class AddPrepaidCreditAmountCentsToInvoices < ActiveRecord::Migration[7.0]
  class WalletTransaction < ApplicationRecord
    belongs_to :wallet
  end

  class Wallet < ApplicationRecord
  end

  def change
    add_column :invoices, :prepaid_credit_amount_cents, :bigint, null: false, default: 0

    reversible do |dir|
      dir.up do
        currency_list = WalletTransaction.joins(:wallet).pluck('DISTINCT(wallets.balance_currency)')
        next if currency_list.blank?

        currency_sql = currency_list.each_with_object([]) do |code, currencies|
          currency = Money::Currency.new(code)
          currencies << "('#{code}', #{currency.exponent}, #{currency.subunit_to_unit})"
        end

        execute <<-SQL
          WITH transaction_total AS (
            SELECT
              wallet_transactions.invoice_id,
              (ROUND(SUM(wallet_transactions.amount), currencies.exponent) * currencies.subunit_to_unit) AS amount_cents
            FROM wallet_transactions
              INNER JOIN wallets ON wallet_transactions.wallet_id = wallets.id
              INNER JOIN (
                SELECT *
                FROM (VALUES #{currency_sql.join(", ")}) AS t(currency, exponent, subunit_to_unit)
              ) currencies ON currencies.currency = wallets.balance_currency
            GROUP BY wallet_transactions.invoice_id, currencies.currency, currencies.exponent, currencies.subunit_to_unit
          )
          UPDATE invoices
          SET prepaid_credit_amount_cents = transaction_total.amount_cents
          FROM transaction_total
          WHERE invoices.id = transaction_total.invoice_id
        SQL
      end
    end
  end
end
