# frozen_string_literal: true

class AddInAdvanceChargePeriodicInvoicingReason < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!
  def up
    safety_assured do
      execute <<-SQL
      ALTER TYPE subscription_invoicing_reason ADD VALUE IF NOT EXISTS 'in_advance_charge_periodic';
      SQL
    end
  end

  def down
  end
end
