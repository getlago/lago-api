# frozen_string_literal: true

class FillSyncWithProviderField < ActiveRecord::Migration[7.0]
  def change
    LagoApi::Application.load_tasks
    Rake::Task['customers:populate_sync_with_provider'].invoke
  end
end
