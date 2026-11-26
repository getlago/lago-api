# frozen_string_literal: true

class UpdateExportsProductFiltersToVersion2 < ActiveRecord::Migration[8.1]
  def change
    update_view :exports_product_filters, version: 2, revert_to_version: 1
  end
end
