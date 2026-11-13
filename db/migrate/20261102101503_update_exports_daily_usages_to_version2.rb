# frozen_string_literal: true

class UpdateExportsDailyUsagesToVersion2 < ActiveRecord::Migration[8.0]
  def change
    update_view :exports_daily_usages, version: 2, revert_to_version: 1
  end
end
