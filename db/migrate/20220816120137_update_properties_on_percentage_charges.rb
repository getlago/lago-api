# frozen_string_literal: true

class UpdatePropertiesOnPercentageCharges < ActiveRecord::Migration[7.0]
  def change
    LagoApi::Application.load_tasks
  end
end
