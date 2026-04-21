# frozen_string_literal: true

class RemovePresentationBreakdownsUniqueFeeIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    remove_index :presentation_breakdowns, :fee_id, name: "index_presentation_breakdowns_on_fee_id", algorithm: :concurrently, if_exists: true
  end

  def down
    add_index :presentation_breakdowns, :fee_id, name: "index_presentation_breakdowns_on_fee_id", algorithm: :concurrently, if_not_exists: true
  end
end
