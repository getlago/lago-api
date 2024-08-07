# frozen_string_literal: true

class RenameProgressiveBillingTresholds < ActiveRecord::Migration[7.1]
  def change
    rename_table :progressive_billing_tresholds, :usage_tresholds
  end
end
