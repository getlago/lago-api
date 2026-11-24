# frozen_string_literal: true

class AddRecordDeletionTriggerToContractRateCardsTerms < ActiveRecord::Migration[8.1]
  def up
    safety_assured do
      # Deferred so the tombstone is stamped as the transaction commits (see AddRecordDeletionTriggers).
      execute <<~SQL
        CREATE CONSTRAINT TRIGGER record_deletions_on_contract_rate_cards_terms
        AFTER DELETE ON contract_rate_cards_terms
        DEFERRABLE INITIALLY DEFERRED
        FOR EACH ROW
        EXECUTE FUNCTION record_deletion();
      SQL
    end
  end

  def down
    safety_assured do
      execute "DROP TRIGGER IF EXISTS record_deletions_on_contract_rate_cards_terms ON contract_rate_cards_terms;"
    end
  end
end
