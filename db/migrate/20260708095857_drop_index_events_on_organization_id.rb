# frozen_string_literal: true

class DropIndexEventsOnOrganizationId < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    remove_index :events, name: :index_events_on_organization_id, algorithm: :concurrently, if_exists: true
  end

  def down
    add_index :events, :organization_id, name: :index_events_on_organization_id, algorithm: :concurrently, if_not_exists: true
  end
end
