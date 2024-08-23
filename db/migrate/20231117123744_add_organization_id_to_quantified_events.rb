# frozen_string_literal: true

class AddOrganizationIdToQuantifiedEvents < ActiveRecord::Migration[7.0]
  def up
    safety_assured do
      add_reference :quantified_events, :organization, type: :uuid, null: true, index: true, foreign_key: true

      execute <<-SQL
      UPDATE quantified_events
      SET organization_id = customers.organization_id
      FROM customers
      WHERE quantified_events.customer_id = customers.id
      SQL

      change_column_null :quantified_events, :organization_id, false
      remove_column :quantified_events, :customer_id
      add_index :quantified_events,
        %i[organization_id external_subscription_id billable_metric_id],
        name: 'index_search_quantified_events'
    end
  end

  def down
    add_reference :quantified_events, :customer, type: :uuid, null: true, index: true, foreign_key: true

    execute <<-SQL
      UPDATE quantified_events
      SET customer_id = subscriptions.customer_id
      FROM subscriptions
        INNER JOIN customers ON customers.id = subscriptions.customer_id
      WHERE quantified_events.external_subscription_id = subscriptions.external_id
        AND customers.organization_id = quantified_events.organization_id
    SQL

    change_column_null :quantified_events, :customer_id, false
    remove_column :quantified_events, :organization_id
  end
end
