# frozen_string_literal: true

class RemoveIntegrationReferenceFromErrorDetail < ActiveRecord::Migration[7.1]
  def up
    safety_assured do
      change_table :error_details, bulk: true do |t|
        t.remove :error_code
        t.remove_references :integration, polymorphic: true
        t.integer :error_code, null: false, default: 0, index: true
      end
    end
  end

  def down
    change_table :error_details, bulk: true do |t|
      t.remove :error_code
      t.references :integration, polymorphic: true
      t.string :error_code, index: true, null: false, default: 'not_provided'
    end
  end
end
