# frozen_string_literal: true

class FillFrequencyDurationRemainingField < ActiveRecord::Migration[7.0]
  def change
    LagoApi::Application.load_tasks
    Rake::Task["applied_coupons:populate_frequency_duration_remaining"].invoke
  end
end
