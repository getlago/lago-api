# frozen_string_literal: true

class CreateCustomerSequentialIdTrigger < ActiveRecord::Migration[8.0]
  def up
    safety_assured do
      execute <<~SQL
        CREATE OR REPLACE FUNCTION set_customer_sequential_id()
        RETURNS trigger AS $$
        DECLARE
          next_id bigint;
          org_prefix text;
        BEGIN
          IF NEW.sequential_id IS NULL THEN
            -- Timeout matches the Ruby advisory lock timeout_seconds: 10
            SET LOCAL lock_timeout = '10s';
            -- Acquire a transaction-level advisory lock per organization to prevent races
            PERFORM pg_advisory_xact_lock(hashtext(NEW.organization_id::text));

            SELECT COALESCE(MAX(sequential_id), 0) + 1
            INTO next_id
            FROM customers
            WHERE organization_id = NEW.organization_id;

            NEW.sequential_id := next_id;
          END IF;

          IF NEW.slug IS NULL THEN
            SELECT document_number_prefix INTO org_prefix
            FROM organizations
            WHERE id = NEW.organization_id;

            NEW.slug := org_prefix || '-' || LPAD(NEW.sequential_id::text, GREATEST(3, LENGTH(NEW.sequential_id::text)), '0');
          END IF;

          RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
      SQL

      execute <<~SQL
        CREATE TRIGGER before_customer_insert
        BEFORE INSERT ON customers
        FOR EACH ROW
        EXECUTE FUNCTION set_customer_sequential_id();
      SQL
    end
  end

  def down
    safety_assured do
      execute "DROP TRIGGER IF EXISTS before_customer_insert ON customers;"
      execute "DROP FUNCTION IF EXISTS set_customer_sequential_id();"
    end
  end
end
