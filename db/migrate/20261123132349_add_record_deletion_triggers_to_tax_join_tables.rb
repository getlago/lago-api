# frozen_string_literal: true

class AddRecordDeletionTriggersToTaxJoinTables < ActiveRecord::Migration[8.1]
  TRACKED_TABLES = %w[billing_entities_taxes customers_taxes rate_cards_taxes].freeze

  def up
    safety_assured do
      TRACKED_TABLES.each do |table|
        # Deferred so the tombstone is stamped as the transaction commits (see AddRecordDeletionTriggers).
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
    end
  end
end
