# frozen_string_literal: true

class CreateExportsRateCardsTaxes < ActiveRecord::Migration[8.1]
  def change
    create_view :exports_rate_cards_taxes
  end
end
