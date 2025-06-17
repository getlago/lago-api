# frozen_string_literal: true

class AddLagoVersionToVersions < ActiveRecord::Migration[7.1]
  def change
    add_column :versions, :lago_version, :string
  end
end
