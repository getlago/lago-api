# frozen_string_literal: true

class BackfillCustomerSearchText < ActiveRecord::Migration[8.0]
  def up
    safety_assured do
      execute <<-SQL
        UPDATE customers
        SET search_text = CONCAT_WS(' ', name, firstname, lastname, external_id, email)
        WHERE search_text = '' OR search_text IS NULL
      SQL
    end
  end

  def down
    # No-op: the trigger keeps populating search_text on writes.
  end
end
