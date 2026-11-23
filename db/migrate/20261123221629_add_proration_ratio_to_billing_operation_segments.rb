# frozen_string_literal: true

class AddProrationRatioToBillingOperationSegments < ActiveRecord::Migration[8.1]
  def change
    # This table has no production rows; a default could turn partial coverage into a full charge.
    add_column :billing_operation_segments, :proration_ratio, :decimal, precision: 30, scale: 10, null: false, if_not_exists: true # rubocop:disable Rails/NotNullColumn
  end
end
