# frozen_string_literal: true

class AddInvoiceableToCharges < ActiveRecord::Migration[7.0]
  def change
    add_column :charges, :invoiceable, :boolean, null: false, default: true

    safety_assured do
      reversible do |dir|
        dir.up do
          execute <<-SQL
          UPDATE charges
          SET invoiceable = false
          WHERE pay_in_advance = true;
          SQL
        end
      end
    end
  end
end
