# frozen_string_literal: true

class AddMetadataToCreditNotes < ActiveRecord::Migration[8.0]
  def up
    safety_assured do
      change_table :credit_notes, bulk: true do |t|
        t.uuid :metadata_id, comment: "Reference to the credit note metadata"

        t.index [:metadata_id, :id, :organization_id],
          where: "metadata_id IS NOT NULL",
          unique: true,
          name: "index_credit_notes_metadata_fk"
      end

      execute <<-SQL.squish
        ALTER TABLE credit_notes
        ADD CONSTRAINT fk_credit_notes_metadata
        FOREIGN KEY (metadata_id, id, organization_id)
        REFERENCES item_metadata(id, owner_id, organization_id)
        DEFERRABLE INITIALLY DEFERRED;
      SQL
    end
  end

  def down
    safety_assured do
      change_table :credit_notes, bulk: true do |t|
        t.remove :metadata_id
      end
    end
  end
end
