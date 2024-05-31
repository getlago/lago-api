# frozen_string_literal: true

class EventsTransactionIdUniqueness < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_index(
      :events,
      %i[organization_id external_subscription_id transaction_id],
      unique: true,
      name: 'index_unique_transaction_id'
    )

    remove_index :events, %i[subscription_id transaction_id]
  end
end
