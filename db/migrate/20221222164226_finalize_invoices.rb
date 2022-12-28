# frozen_string_literal: true

class FinalizeInvoices < ActiveRecord::Migration[7.0]
  def change
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
