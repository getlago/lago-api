# frozen_string_literal: true

class MigrateAppliedTaxesToBillingEntities < ActiveRecord::Migration[7.2]
  class Organization < ApplicationRecord
    attribute :document_numbering, :string
  end

  def up
    Organization.find_each do |organization|
      Tax.where(organization_id: organization.id, applied_to_organization: true).find_each do |tax|
        BillingEntity::AppliedTax.find_or_create_by!(
          billing_entity_id: organization.id,
          tax_id: tax.id
        )
      end
    end
  end
end
