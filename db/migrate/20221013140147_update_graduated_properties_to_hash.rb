# frozen_string_literal: true

class UpdateGraduatedPropertiesToHash < ActiveRecord::Migration[7.0]
  def change
    # NOTE: Wait to ensure workers are loaded with the added tasks
    MigrationTaskJob.set(wait: 20.seconds).perform_later("charges:update_graduated_properties_to_hash")
  end
end
