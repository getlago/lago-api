# frozen_string_literal: true

class CreateExportsPlanRateCards < ActiveRecord::Migration[8.1]
  def change
    create_view :exports_plan_rate_cards
  end
end
