class AddAddOnToFees < ActiveRecord::Migration[7.0]
  def change
    add_reference :fees, :add_on, type: :uuid, foreign_key: true, index: true
  end
end
