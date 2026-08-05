# frozen_string_literal: true

class RemoveShareTokenIndexFromQuoteVersions < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  # The quote sharing feature is not ready and `share_token` is now ignored by the
  # model, so its unique index is unused. Drop it; the column itself stays. `down`
  # recreates the index for when the feature lands.
  def up
    remove_index :quote_versions,
      name: "index_unique_quote_versions_on_share_token",
      algorithm: :concurrently,
      if_exists: true
  end

  def down
    add_index :quote_versions, :share_token,
      unique: true,
      algorithm: :concurrently,
      name: "index_unique_quote_versions_on_share_token",
      if_not_exists: true
  end
end
