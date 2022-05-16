# frozen_string_literal: true

class DropAmountFromCharges < ActiveRecord::Migration[7.0]
  def change
    Charge.find_each do |charge|
      charge.update_column(
        :properties,
        {
          amount_cents: charge.amount_cents,
        },
      )
    end

    remove_column :charges, :amount_cents
  end
end
