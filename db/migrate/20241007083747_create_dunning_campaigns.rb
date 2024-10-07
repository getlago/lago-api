# frozen_string_literal: true

class CreateDunningCampaigns < ActiveRecord::Migration[7.1]
  def change
    create_table :dunning_campaigns, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true

      t.string :name, null: false
      t.string :code, null: false
      t.text :description
      t.boolean :applied_to_organization, null: false, default: false
      t.integer :days_between_attempts, null: false, default: 1
      t.integer :max_attempts, null: false, default: 1

      t.timestamps

      t.index %i[organization_id code], unique: true
    end
  end
end
