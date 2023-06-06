# TODO:
# [] Use datetime instead of timestamp when setting fees

# frozen_string_literal: true

class AddBoundariesToInvoiceSubscriptions < ActiveRecord::Migration[7.0]
  def change
    change_table(:invoice_subscriptions, bulk: true) do |t|
      t.column :timestamp, :datetime
      t.column :from_datetime, :datetime
      t.column :to_datetime, :datetime
      t.column :charges_from_datetime, :datetime
      t.column :charges_to_datetime, :datetime
    end

    reversible do |dir|
      dir.up do
        execute <<-SQL
          /* Unify fees->timestamp to be a required timestamp */
          UPDATE fees
          SET properties['timestamp'] = to_jsonb(CASE
          WHEN properties?'timestamp'
          THEN CASE
            WHEN properties->>'timestamp' ~ '^[0-9\.]+$' /* unix timestamp */
            THEN
              to_timestamp((properties->>'timestamp')::integer)::timestamp(0)
            ELSE
              (properties->>'timestamp')::timestamp(0)
            END
          ELSE
            created_at::timestamp(0)
          END);

          UPDATE invoice_subscriptions
          /* Set timestamp on invoice_subscriptions */
          SET timestamp = CASE
            WHEN properties?'timestamp'
            THEN CASE
              WHEN properties->>'timestamp' ~ '^[0-9\.]+$' /* unix timestamp */
              THEN
                to_timestamp((properties->>'timestamp')::integer)::timestamp(0)
              ELSE
                (properties->>'timestamp')::timestamp(0)
              END
            ELSE /* null timestamp */
              (SELECT(properties->>'timestamp')
              FROM fees
              WHERE fees.subscription_id = invoice_subscriptions.subscription_id
              AND fees.invoice_id = invoice_subscriptions.invoice_id
              ORDER BY fees.created_at ASC
              LIMIT 1)::timestamp(0)
            END,
          /* Set from_datetime on invoice_subscriptions */
          from_datetime = CASE
            WHEN properties?'from_datetime'
            THEN CASE
              WHEN properties->>'from_datetime' ~ '^[0-9\.]+$' /* unix timestamp */
              THEN
                to_timestamp((properties->>'from_datetime')::integer)::timestamp(0)
              ELSE
                (properties->>'from_datetime')::timestamp(0)
              END
            ELSE /* null timestamp */
              (SELECT(properties->>'from_datetime')
              FROM fees
              WHERE fees.subscription_id = invoice_subscriptions.subscription_id
              AND fees.invoice_id = invoice_subscriptions.invoice_id
              ORDER BY fees.created_at ASC
              LIMIT 1)::timestamp(0)
            END,
          /* Set to_datetime on invoice_subscriptions */
          to_datetime = CASE
            WHEN properties?'to_datetime'
            THEN CASE
              WHEN properties->>'to_datetime' ~ '^[0-9\.]+$' /* unix timestamp */
              THEN
                to_timestamp((properties->>'to_datetime')::integer)::timestamp(0)
              ELSE
                (properties->>'to_datetime')::timestamp(0)
              END
            ELSE /* null timestamp */
              (SELECT(properties->>'to_datetime')
              FROM fees
              WHERE fees.subscription_id = invoice_subscriptions.subscription_id
              AND fees.invoice_id = invoice_subscriptions.invoice_id
              ORDER BY fees.created_at ASC
              LIMIT 1)::timestamp(0)
            END,
          /* Set charges_from_datetime on invoice_subscriptions */
          charges_from_datetime = CASE
            WHEN properties?'charges_from_datetime'
            THEN CASE
              WHEN properties->>'charges_from_datetime' ~ '^[0-9\.]+$' /* unix timestamp */
              THEN
                to_timestamp((properties->>'charges_from_datetime')::integer)::timestamp(0)
              ELSE
                (properties->>'charges_from_datetime')::timestamp(0)
              END
            ELSE /* null timestamp */
              (SELECT(properties->>'charges_from_datetime')
              FROM fees
              WHERE fees.subscription_id = invoice_subscriptions.subscription_id
              AND fees.invoice_id = invoice_subscriptions.invoice_id
              ORDER BY fees.created_at ASC
              LIMIT 1)::timestamp(0)
            END,
          /* Set charges_to_datetime on invoice_subscriptions */
          charges_to_datetime = CASE
            WHEN properties?'charges_to_datetime'
            THEN CASE
              WHEN properties->>'charges_to_datetime' ~ '^[0-9\.]+$' /* unix timestamp */
              THEN
                to_timestamp((properties->>'charges_to_datetime')::integer)::timestamp(0)
              ELSE
                (properties->>'charges_to_datetime')::timestamp(0)
              END
            ELSE /* null timestamp */
              (SELECT(properties->>'charges_to_datetime')
              FROM fees
              WHERE fees.subscription_id = invoice_subscriptions.subscription_id
              AND fees.invoice_id = invoice_subscriptions.invoice_id
              ORDER BY fees.created_at ASC
              LIMIT 1)::timestamp(0)
            END
        SQL
      end
    end
  end
end
