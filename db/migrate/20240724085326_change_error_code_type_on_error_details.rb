# frozen_string_literal: true

class ChangeErrorCodeTypeOnErrorDetails < ActiveRecord::Migration[7.1]
  def up
    change_table :error_details, bulk: true do |t|
      t.remove :error_code
      t.integer :error_code, null: false, default: 0, index: true
    end
  end

  def down
    change_table :error_details, bulk: true do |t|
      t.remove :error_code
      t.string :error_code, index: true, null: false, default: 'not_provided'
    end
  end
end
