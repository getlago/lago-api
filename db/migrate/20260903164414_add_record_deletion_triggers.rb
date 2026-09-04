# frozen_string_literal: true

class AddRecordDeletionTriggers < ActiveRecord::Migration[8.0]
  TRACKED_TABLES = %w[fees fees_taxes invoice_subscriptions invoices_taxes credit_notes_taxes].freeze

  def up
    safety_assured do
      execute <<~SQL
        CREATE OR REPLACE FUNCTION record_deletion() RETURNS trigger
        LANGUAGE plpgsql AS $$
        DECLARE
          -- All three timestamps come from one value: leaving created_at/updated_at to the
          -- column defaults would stamp them with the transaction start, which can be far
          -- behind the delete and behind the pipeline cursor by the time the row commits.
          deleted_time timestamp := statement_timestamp() AT TIME ZONE 'UTC';
        BEGIN
          INSERT INTO record_deletions (organization_id, record_table, record_id, deleted_at, created_at, updated_at)
          SELECT deleted_rows.organization_id, TG_TABLE_NAME, deleted_rows.id, deleted_time, deleted_time, deleted_time
          FROM deleted_rows;

          RETURN NULL;
        END;
        $$;
      SQL

      TRACKED_TABLES.each do |table|
        execute <<~SQL
          CREATE TRIGGER record_deletions_on_#{table}
          AFTER DELETE ON #{table}
          REFERENCING OLD TABLE AS deleted_rows
          FOR EACH STATEMENT
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
