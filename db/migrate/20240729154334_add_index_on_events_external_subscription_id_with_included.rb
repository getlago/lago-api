# frozen_string_literal: true

class AddIndexOnEventsExternalSubscriptionIdWithIncluded < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :events, %i[external_subscription_id code timestamp],
      name: 'index_events_on_external_subscription_id_with_included',
      where: 'deleted_at IS NULL',
      algorithm: :concurrently,
      if_not_exists: true,
      include: %i[organization_id properties]
  end
end
