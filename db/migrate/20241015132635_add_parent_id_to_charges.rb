# frozen_string_literal: true

class AddParentIdToCharges < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    safety_assured do
      add_reference :charges, :parent, type: :uuid, null: true, index: true, foreign_key: {to_table: :charges}
    end
  end
end
