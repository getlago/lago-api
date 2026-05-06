# frozen_string_literal: true

class AddEventsOrganizationCodeTimestampIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :events,
      [:organization_id, :code, :timestamp],
      order: {timestamp: :desc},
      where: "deleted_at IS NULL",
      name: "index_events_on_organization_id_code_and_timestamp",
      algorithm: :concurrently,
      if_not_exists: true
  end
end
