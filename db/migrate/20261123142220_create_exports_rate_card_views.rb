# frozen_string_literal: true

class CreateExportsRateCardViews < ActiveRecord::Migration[8.1]
  def change
    create_view :exports_rate_cards, version: 1
    create_view :exports_rate_card_rates, version: 1
    create_view :exports_rate_phases, version: 1
    create_view :exports_rate_overrides, version: 1
  end
end
