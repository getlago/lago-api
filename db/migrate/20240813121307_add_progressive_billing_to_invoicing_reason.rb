# frozen_string_literal: true

class AddProgressiveBillingToInvoicingReason < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    safety_assured do
      execute <<-SQL
      ALTER TYPE subscription_invoicing_reason ADD VALUE IF NOT EXISTS 'progressive_billing';
      SQL
    end
  end

  def down
  end
end
