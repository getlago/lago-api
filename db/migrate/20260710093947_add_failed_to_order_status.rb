# frozen_string_literal: true

class AddFailedToOrderStatus < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    safety_assured do
      execute "ALTER TYPE order_status ADD VALUE IF NOT EXISTS 'failed'"
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "PostgreSQL cannot remove a value from an enum type"
  end
end
