# frozen_string_literal: true

class FillEventTimestamps < ActiveRecord::Migration[7.0]
  def change
    LagoApi::Application.load_tasks
    Rake::Task['events:fill_timestamp'].invoke
  end
end
