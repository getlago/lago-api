# frozen_string_literal: true

class UpdateTimezones < ActiveRecord::Migration[8.0]
  def change
    mapping = {
      "Asia/Rangoon" => "Asia/Yangon",
      "Europe/Kiev" => "Europe/Kyiv",
      "America/Godthab" => "America/Nuuk"
    }

    mapping.each do |old_timezone, new_timezone|
      # rubocop:disable Rails/SkipsModelValidations
      Organization.where(timezone: old_timezone).update_all(timezone: new_timezone)
      Customer.where(timezone: old_timezone).update_all(timezone: new_timezone)
      Invoice.where(timezone: old_timezone).update_all(timezone: new_timezone)
      BillingEntity.where(timezone: old_timezone).update_all(timezone: new_timezone)
      # rubocop:enable Rails/SkipsModelValidations
    end
  end
end
