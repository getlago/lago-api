# frozen_string_literal: true

class AddSubscriptionIdToEvents < ActiveRecord::Migration[7.0]
  def change
    remove_index :events, %i[organization_id transaction_id]

    safety_assured do
      add_reference :events, :subscription, type: :uuid, foreign_key: true
      add_index :events, %i[subscription_id code]
      add_index :events, %i[subscription_id transaction_id], unique: true
    end
  end
end
