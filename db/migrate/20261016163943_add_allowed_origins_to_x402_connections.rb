# frozen_string_literal: true

class AddAllowedOriginsToX402Connections < ActiveRecord::Migration[8.1]
  def change
    add_column :x402_connections, :allowed_origins, :string, array: true, default: [], null: false, if_not_exists: true
  end
end
