# frozen_string_literal: true

class AddCurrentPackageCountToEvents < ActiveRecord::Migration[7.0]
  def change
    add_column :events, :current_package_count, :bigint
  end
end
