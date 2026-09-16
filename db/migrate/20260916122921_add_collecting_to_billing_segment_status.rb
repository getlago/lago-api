# frozen_string_literal: true

class AddCollectingToBillingSegmentStatus < ActiveRecord::Migration[8.0]
  def up
    add_enum_value :billing_segment_status, "collecting", before: "processing", if_not_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Cannot remove collecting from billing_segment_status"
  end
end
