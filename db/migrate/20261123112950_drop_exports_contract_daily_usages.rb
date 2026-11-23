# frozen_string_literal: true

class DropExportsContractDailyUsages < ActiveRecord::Migration[8.1]
  def change
    drop_view :exports_contract_daily_usages, revert_to_version: 1
  end
end
