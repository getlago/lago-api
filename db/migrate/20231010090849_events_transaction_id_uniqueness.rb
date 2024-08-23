# frozen_string_literal: true

class EventsTransactionIdUniqueness < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    safety_assured do
      add_index(
        :events,
        %i[organization_id external_subscription_id transaction_id],
        unique: true,
        name: 'index_unique_transaction_id'
      )
    end
    remove_index :events, %i[subscription_id transaction_id]
  end
end
