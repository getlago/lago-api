# frozen_string_literal: true

class UpdatePropertiesOnPercentageCharges < ActiveRecord::Migration[7.0]
  def change
    LagoApi::Application.load_tasks
    Rake::Task["charges:update_properties_for_free_units"].invoke
  end
end
