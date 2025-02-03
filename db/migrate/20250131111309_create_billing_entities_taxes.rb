#frozen_string_literal: true

class CreateBillingEntitiesTaxes < ActiveRecord::Migration[7.1]
  def change
    create_table :billing_entities_taxes, id: false do |t|
      t.belongs_to :billing_entity
      t.belongs_to :tax
    end
  end
end
