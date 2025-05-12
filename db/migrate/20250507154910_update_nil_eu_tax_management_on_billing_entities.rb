# frozen_string_literal: true

class UpdateNilEuTaxManagementOnBillingEntities < ActiveRecord::Migration[8.0]
  def change
    # rubocop:disable Rails/SkipsModelValidations
    BillingEntity.where(eu_tax_management: nil).update_all(eu_tax_management: false)
    # rubocop:enable Rails/SkipsModelValidations
  end
end
