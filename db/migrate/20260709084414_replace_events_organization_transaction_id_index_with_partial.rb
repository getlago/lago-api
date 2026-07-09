# frozen_string_literal: true

class ReplaceEventsOrganizationTransactionIdIndexWithPartial < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    # The unique index on (organization_id, external_subscription_id, transaction_id)
    # already covers within-subscription lookups; a narrower (transaction_id) partial
    # index still serves organization_id = ? AND transaction_id = ? lookups by seeking
    # on the highly selective transaction_id and filtering on organization_id.
    add_index :events,
      :transaction_id,
      where: "deleted_at IS NULL",
      name: "index_events_on_transaction_id",
      algorithm: :concurrently,
      if_not_exists: true

    remove_index :events,
      name: "index_events_on_organization_id_and_transaction_id",
      algorithm: :concurrently,
      if_exists: true
  end

  def down
    add_index :events,
      [:organization_id, :transaction_id],
      where: "deleted_at IS NULL",
      name: "index_events_on_organization_id_and_transaction_id",
      algorithm: :concurrently,
      if_not_exists: true

    remove_index :events,
      name: "index_events_on_transaction_id",
      algorithm: :concurrently,
      if_exists: true
  end
end
