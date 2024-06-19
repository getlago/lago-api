class AddInAdvanceChargePeriodicInvoicingReason < ActiveRecord::Migration[7.0]
  def up
    execute <<-SQL
      ALTER TYPE subscription_invoicing_reason ADD VALUE IF NOT EXISTS 'in_advance_charge_periodic';
    SQL
  end

  def down
  end
end
