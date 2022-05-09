# freozen_string_literal: true

class AddPropertiesAttributeToCharges < ActiveRecord::Migration[7.0]
  def change
    add_column :charges, :properties, :jsonb, null: false, default: '{}'
  end
end
