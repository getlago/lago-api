# frozen_string_literal: true

class RenameStatusOnInvoices < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      rename_column :invoices, :status, :payment_status
      add_column :invoices, :status, :integer, null: false, default: 0

      reversible do |dir|
        dir.up do
          # Mark all existing invoices as finalized.
          execute <<-SQL
          UPDATE invoices SET status = 1;
          SQL
        end
      end
    end
  end
end
