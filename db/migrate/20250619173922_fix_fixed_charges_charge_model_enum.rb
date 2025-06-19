class FixFixedChargesChargeModelEnum < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    safety_assured do
      execute <<-SQL
        ALTER TYPE fixed_charges_charge_model ADD VALUE 'graduated';
      SQL
    end
  end
end
