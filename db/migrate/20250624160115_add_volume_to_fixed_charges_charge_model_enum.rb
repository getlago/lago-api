# frozen_string_literal: true

class AddVolumeToFixedChargesChargeModelEnum < ActiveRecord::Migration[8.0]
  def change
    safety_assured do
      execute <<-SQL
        ALTER TYPE fixed_charges_charge_model ADD VALUE 'volume';
      SQL
    end
  end
end
