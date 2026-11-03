# frozen_string_literal: true

# Customers are backfilled by the migrations:backfill_customers_payment_term rake task.
class BackfillPaymentTerms < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    safety_assured do
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
