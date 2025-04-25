# frozen_string_literal: true

class AddTotalPaidAmountCentsToInvoices < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    add_column :invoices, :total_paid_amount_cents, :bigint, null: true
    # Backfill
    Invoice.in_batches(of: 10_000).each do |batch|
      batch.update_all(total_paid_amount_cents: 0)
    end

    safety_assured do
      execute <<~SQL
        ALTER TABLE invoices ALTER COLUMN total_paid_amount_cents SET DEFAULT 0;
      SQL
      execute <<~SQL
        ALTER TABLE invoices ALTER COLUMN total_paid_amount_cents SET NOT NULL;
      SQL
    end
  end

  def down
    # Remove the column
    remove_column :invoices, :total_paid_amount_cents
  end
end
