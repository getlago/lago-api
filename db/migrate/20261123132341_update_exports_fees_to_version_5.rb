# frozen_string_literal: true

class UpdateExportsFeesToVersion5 < ActiveRecord::Migration[8.1]
  def change
    update_view :exports_fees, version: 5, revert_to_version: 4
  end
end
