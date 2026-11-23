# frozen_string_literal: true

class UpdateExportsDailyUsagesToVersion3 < ActiveRecord::Migration[8.1]
  def change
    update_view :exports_daily_usages, version: 3, revert_to_version: 2
  end
end
