# frozen_string_literal: true

class AddRecordDeletionTriggerToPlansTaxes < ActiveRecord::Migration[8.1]
  def up
    safety_assured do
      # Deferred so the tombstone is stamped as the transaction commits (see AddRecordDeletionTriggers).
      execute <<~SQL
        CREATE CONSTRAINT TRIGGER record_deletions_on_plans_taxes
        AFTER DELETE ON plans_taxes
        DEFERRABLE INITIALLY DEFERRED
        FOR EACH ROW
        EXECUTE FUNCTION record_deletion();
      SQL
    end
  end

  def down
    safety_assured do
      execute "DROP TRIGGER IF EXISTS record_deletions_on_plans_taxes ON plans_taxes;"
    end
  end
end
