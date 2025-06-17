# frozen_string_literal: true

class AddVersionToInvoices < ActiveRecord::Migration[7.0]
  def up
    add_column :invoices, :version_number, :integer, null: false, default: 2
    safety_assured do
      execute <<-SQL
      UPDATE invoices
      SET version_number = 1
      WHERE legacy = 't'
      SQL

      remove_column :invoices, :legacy
    end
  end

  def down
    add_column :invoices, :legacy, :boolean, null: false, default: false

    execute <<-SQL
      UPDATE invoices
      SET legacy = 't'
      WHERE version_number = 1
    SQL

    remove_column :invoices, :version_number
  end
end
