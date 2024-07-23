# frozen_string_literal: true

class RemoveIntegrationReferenceFromErrorDetail < ActiveRecord::Migration[7.1]
  def change
    change_table :error_details do |t|
      t.remove_references :integration, polymorphic: true
    end
  end
end
