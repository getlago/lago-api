# frozen_string_literal: true

class AddDescriptionToCreditNotes < ActiveRecord::Migration[7.0]
  def change
    add_column :credit_notes, :description, :text
  end
end
