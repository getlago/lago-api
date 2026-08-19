# frozen_string_literal: true

class BackfillPaymentTerms < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  # Plain AR class detached from app/models/customer.rb so the migration
  # does not depend on the model's current enums and validations.
  class MigrationCustomer < ActiveRecord::Base
    self.table_name = "customers"
  end

  def up
    safety_assured do
      backfill_customers
      backfill_billing_entities
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "backfilled payment terms cannot be distinguished from user values"
  end

  private

  def backfill_customers
    MigrationCustomer
      .where(payment_term: nil).where.not(net_payment_term: nil)
      .in_batches(of: 10_000) do |batch|
        batch.update_all("payment_term = jsonb_build_object('term_type', 'net', 'days', net_payment_term)") # rubocop:disable Rails/SkipsModelValidations
      end
  end

  def backfill_billing_entities
    execute <<~SQL
      UPDATE billing_entities
      SET payment_term = jsonb_build_object('term_type', 'net', 'days', net_payment_term)
      WHERE payment_term IS NULL AND net_payment_term IS NOT NULL
    SQL
  end
end
