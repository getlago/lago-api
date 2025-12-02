# frozen_string_literal: true

class AddExpectedFinalizationDateToInvoices < ActiveRecord::Migration[8.0]
  def up
    add_column :invoices, :expected_finalization_date, :date

    safety_assured do
      execute <<-SQL
        UPDATE invoices
        SET expected_finalization_date = issuing_date
      SQL
    end
  end

  def down
    remove_column :invoices, :expected_finalization_date
  end
end
