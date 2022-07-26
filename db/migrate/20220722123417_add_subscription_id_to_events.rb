# frozen_string_literal: true

class AddSubscriptionIdToEvents < ActiveRecord::Migration[7.0]
  def change
    remove_index :events, %i[organization_id transaction_id]

    add_reference :events, :subscription, type: :uuid, foreign_key: true
    add_index :events, %i[subscription_id code]
    add_index :events, %i[subscription_id transaction_id], unique: true

    LagoApi::Application.load_tasks
    Rake::Task['events:fill_subscription'].invoke
  end
end
