# frozen_string_literal: true

class ChangeFeesBoundaries < ActiveRecord::Migration[7.0]
  def change
    # NOTE: Wait to ensure workers are loaded with the added tasks
    MigrationTaskJob.set(wait: 40.seconds).perform_later('fees:migrate_boundaries')
  end
end
