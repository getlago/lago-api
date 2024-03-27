# frozen_string_literal: true

class UpdateFeeType < ActiveRecord::Migration[7.0]
  def change
    LagoApi::Application.load_tasks
    Rake::Task["fees:fill_fee_type"].invoke
  end
end
