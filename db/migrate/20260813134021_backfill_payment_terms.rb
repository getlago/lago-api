# frozen_string_literal: true

class BackfillPaymentTerms < ActiveRecord::Migration[8.0]
  def up
    safety_assured do
      execute <<~SQL
        UPDATE customers
        SET payment_term = jsonb_build_object('term_type', 'net', 'days', net_payment_term)
        WHERE payment_term IS NULL AND net_payment_term IS NOT NULL
      SQL

      execute <<~SQL
        UPDATE billing_entities
        SET payment_term = jsonb_build_object('term_type', 'net', 'days', net_payment_term)
        WHERE payment_term IS NULL AND net_payment_term IS NOT NULL
      SQL
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "backfilled payment terms cannot be distinguished from user values"
  end
end
