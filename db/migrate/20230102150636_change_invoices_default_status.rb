# frozen_string_literal: true

class ChangeInvoicesDefaultStatus < ActiveRecord::Migration[7.0]
  def up
    change_column_default :invoices, :status, 1

    execute <<-SQL
      UPDATE invoices SET status = 1;
    SQL
  end

  def down
    change_column_default :invoices, :status, 0
  end
end
