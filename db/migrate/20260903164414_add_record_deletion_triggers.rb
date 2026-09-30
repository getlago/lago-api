# frozen_string_literal: true

class AddRecordDeletionTriggers < ActiveRecord::Migration[8.0]
  TRACKED_TABLES = %w[fees fees_taxes invoice_subscriptions invoices_taxes credit_notes_taxes].freeze

  def up
    safety_assured do
      execute <<~SQL
        CREATE OR REPLACE FUNCTION record_deletion() RETURNS trigger
        LANGUAGE plpgsql AS $$
        DECLARE
          deleted_time timestamp := clock_timestamp() AT TIME ZONE 'UTC';
        BEGIN
          INSERT INTO record_deletions (organization_id, record_table, record_id, deleted_at, created_at, updated_at)
          VALUES (OLD.organization_id, TG_TABLE_NAME, OLD.id, deleted_time, deleted_time, deleted_time);

          RETURN NULL;
        END;
        $$;
      SQL

      TRACKED_TABLES.each do |table|
        # Deferred so the tombstone is stamped as the transaction commits. An immediate
        # trigger stamps it when the row is deleted, which on a long transaction is far
        # enough ahead of the commit that an incremental export can advance its cursor
        # past the tombstone before the row is ever visible to it.
        execute <<~SQL
          CREATE CONSTRAINT TRIGGER record_deletions_on_#{table}
          AFTER DELETE ON #{table}
          DEFERRABLE INITIALLY DEFERRED
          FOR EACH ROW
          EXECUTE FUNCTION record_deletion();
        SQL
      end
    end
  end

  def down
    safety_assured do
      TRACKED_TABLES.each do |table|
        execute "DROP TRIGGER IF EXISTS record_deletions_on_#{table} ON #{table};"
      end

      execute "DROP FUNCTION IF EXISTS record_deletion();"
    end
  end
end
