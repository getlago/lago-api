# frozen_string_literal: true

class FillEventsAttributes < ActiveRecord::Migration[7.0]
  def change
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE events
          SET external_subscription_id = subscriptions.external_id
          FROM subscriptions
            WHERE subscriptions.id = events.subscription_id
            AND events.deleted_at IS NULL;

          UPDATE events
          SET external_customer_id = customers.external_id
          FROM customers
            WHERE customers.id = events.customer_id
            AND events.deleted_at IS NULL;

          UPDATE events
          SET value = events.properties->>billable_metrics.field_name
          FROM billable_metrics
            WHERE billable_metrics.code = events.code
            AND billable_metrics.organization_id = events.organization_id
            AND events.deleted_at IS NULL;
        SQL
      end
    end
  end
end
