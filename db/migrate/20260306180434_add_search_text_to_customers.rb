# frozen_string_literal: true

class AddSearchTextToCustomers < ActiveRecord::Migration[8.0]
  def up
    add_column :customers, :search_text, :text

    safety_assured do
      execute <<-SQL
        CREATE OR REPLACE FUNCTION restore_invariants_on_customers() RETURNS trigger AS $$
          BEGIN
            NEW.search_text := CONCAT_WS(' ', NEW.external_id, NEW.firstname, NEW.lastname, NEW.name, NEW.email);
            RETURN NEW;
          END;
        $$ LANGUAGE plpgsql;
      SQL

      execute <<-SQL
        CREATE TRIGGER restore_invariants
        BEFORE INSERT OR UPDATE ON customers
        FOR EACH ROW
        EXECUTE FUNCTION restore_invariants_on_customers();
      SQL
    end
  end

  def down
    execute <<-SQL
      DROP TRIGGER IF EXISTS restore_invariants ON customers;
    SQL

    execute <<-SQL
      DROP FUNCTION IF EXISTS restore_invariants_on_customers;
    SQL

    # rubocop: disable Lago/NoDropColumnOrTable
    remove_column :customers, :search_text
    # rubocop: enable Lago/NoDropColumnOrTable
  end
end
