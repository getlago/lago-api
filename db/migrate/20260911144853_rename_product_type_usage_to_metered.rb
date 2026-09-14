# frozen_string_literal: true

class RenameProductTypeUsageToMetered < ActiveRecord::Migration[8.0]
  def change
    rename_enum_value :product_type, from: "usage", to: "metered"
  end
end
