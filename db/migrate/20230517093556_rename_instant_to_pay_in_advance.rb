# frozen_string_literal: true

class RenameInstantToPayInAdvance < ActiveRecord::Migration[7.0]
  def change
    add_column :fees, :pay_in_advance, :boolean, null: false, default: false

    safety_assured do
      rename_column :charges, :instant, :pay_in_advance
      rename_column :fees, :instant_event_id, :pay_in_advance_event_id

      reversible do |dir|
        dir.up do
          execute <<-SQL
          UPDATE fees
          SET pay_in_advance = charges.pay_in_advance,
              fee_type = CASE WHEN charges.pay_in_advance = true THEN 0 ELSE fee_type END
          FROM charges
          WHERE fees.charge_id = charges.id;
          SQL
        end
      end
    end
  end
end
