# frozen_string_literal: true

class CreateJobScheduleOverrides < ActiveRecord::Migration[8.0]
  def change
    create_table :job_schedule_overrides, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.string :job_name
      t.integer :frequency_secods
      t.datetime :last_enqueued_at
      t.datetime :enabled_at
      t.datetime :deleted_at

      t.index %i[organization_id job_name], unique: true

      t.timestamps
    end
  end
end
