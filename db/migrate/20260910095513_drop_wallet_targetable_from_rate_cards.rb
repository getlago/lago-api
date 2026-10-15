# frozen_string_literal: true

class DropWalletTargetableFromRateCards < ActiveRecord::Migration[8.0]
  def up
    safety_assured do
      remove_column :rate_cards, :wallet_targetable
    end
  end
end
