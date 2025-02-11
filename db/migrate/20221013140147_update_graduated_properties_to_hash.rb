# frozen_string_literal: true

class UpdateGraduatedPropertiesToHash < ActiveRecord::Migration[7.0]
  class Charge < ApplicationRecord; end

  def up
    # Rename existing volume charge model ranges from `ranges: []` to `volume_ranges: []`
    Charge.where(charge_model: 4).find_each do |charge|
      charge.properties["volume_ranges"] = charge.properties.delete("ranges")
      charge.save!
    end

    # Update graduated charges from array `[]` to hash `graduated_ranges: []`
    Charge.where(charge_model: 1).find_each do |charge|
      charge.properties = {graduated_ranges: charge.properties}
      charge.save!
    end
  end
end
