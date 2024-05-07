# frozen_string_literal: true

class AddBillableMetricIdToPersistedEvents < ActiveRecord::Migration[7.0]
  def change
    add_reference :persisted_events, :billable_metric, type: :uuid

    remove_index :persisted_events, name: :index_search_persisted_events # rubocop:disable Rails/ReversibleMigration
    add_index :persisted_events,
      [:customer_id, :external_subscription_id, :billable_metric_id],
      name: :index_search_persisted_events
  end
end
