# frozen_string_literal: true

class AddChargeFiltersChargeCodeIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    # NOTE: repeated NULLs are allowed, so rows still waiting on the backfill do not trip this
    add_index :charge_filters,
      %i[charge_id code],
      unique: true,
      where: "deleted_at IS NULL",
      algorithm: :concurrently,
      if_not_exists: true,
      name: "index_charge_filters_on_charge_id_and_code"
  end
end
