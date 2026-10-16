# frozen_string_literal: true

class RemoveUnusedBillingSegmentIndexes < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    remove_index :billing_segments, :pricing_unit_id, algorithm: :concurrently, if_exists: true
    remove_index :billing_segments, :rate_card_rate_id, algorithm: :concurrently, if_exists: true
  end

  def down
    add_index :billing_segments, :pricing_unit_id, algorithm: :concurrently, if_not_exists: true
    add_index :billing_segments, :rate_card_rate_id, algorithm: :concurrently, if_not_exists: true
  end
end
