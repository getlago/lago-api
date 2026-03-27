# frozen_string_literal: true

class CreatePresentationBreakdowns < ActiveRecord::Migration[8.0]
  def change
    create_table :presentation_breakdowns, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :fee, null: false, foreign_key: true, type: :uuid, index: {unique: true}

      t.jsonb :breakdowns, null: false, default: []

      t.timestamps
    end
  end
end
