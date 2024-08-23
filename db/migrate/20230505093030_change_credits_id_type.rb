# frozen_string_literal: true

class ChangeCreditsIdType < ActiveRecord::Migration[7.0]
  def up
    safety_assured do
      add_column :credits, :uuid, :uuid, null: false, default: -> { 'gen_random_uuid()' }

      change_table :credits do |t|
        t.remove :id
        t.rename :uuid, :id
      end

      execute 'ALTER TABLE credits ADD PRIMARY KEY (id);'
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
