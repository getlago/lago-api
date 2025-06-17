# frozen_string_literal: true

class AddIssuingDateToCreditNotes < ActiveRecord::Migration[7.0]
  def change
    add_column :credit_notes, :issuing_date, :date

    safety_assured do
      reversible do |dir|
        dir.up do
          execute <<-SQL
          UPDATE credit_notes SET issuing_date = DATE(created_at);
          SQL
        end
      end

      change_column_null :credit_notes, :issuing_date, false
    end
  end
end
