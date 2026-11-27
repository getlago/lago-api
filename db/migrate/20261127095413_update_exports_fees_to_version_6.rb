# frozen_string_literal: true

class UpdateExportsFeesToVersion6 < ActiveRecord::Migration[8.1]
  def change
    update_view :exports_fees, version: 6, revert_to_version: 5
  end
end
