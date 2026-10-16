# frozen_string_literal: true

class CreateExportsRecordDeletions < ActiveRecord::Migration[8.0]
  def change
    create_view :exports_record_deletions
  end
end
