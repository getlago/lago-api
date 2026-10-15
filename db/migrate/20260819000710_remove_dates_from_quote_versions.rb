# frozen_string_literal: true

class RemoveDatesFromQuoteVersions < ActiveRecord::Migration[8.0]
  def change
    # Dropped outright rather than ignored first: the quote feature is not released yet.
    safety_assured do
      remove_column :quote_versions, :start_date, :date # rubocop:disable Lago/NoDropColumnOrTable
      remove_column :quote_versions, :end_date, :date # rubocop:disable Lago/NoDropColumnOrTable
    end
  end
end
