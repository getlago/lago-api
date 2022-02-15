# frozen_string_literal: true

# CreateOrganizations Migration
class CreateOrganizations < ActiveRecord::Migration[7.0]
  def change
    create_table :organizations, id: :uuid do |t|
      t.string :name, null: false
      t.timestamps
    end
  end
end
