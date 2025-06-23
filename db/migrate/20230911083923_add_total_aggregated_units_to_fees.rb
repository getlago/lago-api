# frozen_string_literal: true

class AddTotalAggregatedUnitsToFees < ActiveRecord::Migration[7.0]
  def change
    add_column :fees, :total_aggregated_units, :decimal

    safety_assured do
      reversible do |dir|
        dir.up do
          execute <<-SQL
          UPDATE fees
          SET total_aggregated_units = units
          WHERE fee_type = 0;
          SQL
        end
      end
    end
  end
end
