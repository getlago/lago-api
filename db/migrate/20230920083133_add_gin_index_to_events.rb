# frozen_string_literal: true

class AddGinIndexToEvents < ActiveRecord::Migration[7.0]
  def change
    add_index(:events, :properties, using: 'gin', opclass: :jsonb_path_ops, algorithm: :concurrently)
  end
end
