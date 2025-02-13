# frozen_string_literal: true

class FixChargePropertiesWithDoubleValues < ActiveRecord::Migration[7.1]
  def up
    pairs = [["amount", "graduated_ranges"], ["amount", "graduated_percentage_ranges"], ["amount", "volume_ranges"]]
    pairs.each do |pair|
      ChargeFilter.includes(:charge).where("properties ?& array[:keys]", keys: pair).find_each do |cf|
        fix_charge_filter_properties(cf)
      end
      Charge.where("properties ?& array[:keys]", keys: pair).find_each do |charge|
        fix_charge_properties(charge)
      end
    end
  end

  def down
  end

  private

  def fix_charge_filter_properties(charge_filter)
    result = Charges::FilterChargeModelPropertiesService.call(
      charge: charge_filter.charge, properties: charge_filter.properties
    ).raise_if_error!
    charge_filter.properties = result.properties
    charge_filter.save!
  rescue ActiveRecord::RecordInvalid => e
    say "-" * 50
    say e.message
    say "Please fix the following charge filter manually:"
    say "Failed charge_filter_id: #{charge_filter.id}"
    say "Charge Filter properties: #{charge_filter.properties}"
    say "Charge payment model: #{charge_filter.charge.charge_model}"
  end

  def fix_charge_properties(charge)
    result = Charges::FilterChargeModelPropertiesService.call(
      charge:, properties: charge.properties
    ).raise_if_error!
    charge.properties = result.properties
    charge.save!
  rescue ActiveRecord::RecordInvalid => e
    say "-" * 50
    say e.message
    say "Please fix the following charge manually:"
    say "Failed charge_id: #{charge.id}"
    say "Charge properties: #{charge.properties}"
    say "Charge payment model: #{charge.charge_model}"
  end
end
