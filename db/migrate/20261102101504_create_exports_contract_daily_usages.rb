# frozen_string_literal: true

class CreateExportsContractDailyUsages < ActiveRecord::Migration[8.0]
  def change
    create_view :exports_contract_daily_usages
  end
end
