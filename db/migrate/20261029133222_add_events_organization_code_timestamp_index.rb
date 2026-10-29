# frozen_string_literal: true

# Listing and counting the events of one code must read only kept rows, in timestamp order:
# the non-partial `(organization_id, code)` index makes every match be read from the table to
# check `deleted_at`. `index_events_on_organization_id_and_code` stays until it is unused.
class AddEventsOrganizationCodeTimestampIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # A failed concurrent build leaves an invalid index behind, which `if_not_exists`
    # would then keep: drop it so that a retry builds the index again.
    if index_exists?(:events, nil, name: :index_events_on_organization_id_code_and_timestamp, valid: false)
      remove_index :events, name: :index_events_on_organization_id_code_and_timestamp, algorithm: :concurrently
    end

    add_index :events,
      [:organization_id, :code, :timestamp],
      order: {timestamp: :desc},
      where: "deleted_at IS NULL",
      name: :index_events_on_organization_id_code_and_timestamp,
      algorithm: :concurrently,
      if_not_exists: true
  end

  def down
    remove_index :events, name: :index_events_on_organization_id_code_and_timestamp, algorithm: :concurrently, if_exists: true
  end
end
