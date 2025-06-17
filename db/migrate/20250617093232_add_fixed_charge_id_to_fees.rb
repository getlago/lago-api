# frozen_string_literal: true

class AddFixedChargeIdToFees < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_reference :fees, :fixed_charge, type: :uuid, null: true, index: {algorithm: :concurrently}
  end
end
