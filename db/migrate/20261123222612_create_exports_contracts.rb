# frozen_string_literal: true

class CreateExportsContracts < ActiveRecord::Migration[8.1]
  def change
    create_view :exports_contracts
  end
end
