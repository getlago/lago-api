# frozen_string_literal: true

class FixBillingEntityDocumentNumberingPrefix < ActiveRecord::Migration[8.0]
  class BillingEntity < ApplicationRecord; end

  def up
    # rubocop:disable Rails/SkipsModelValidations
    BillingEntity.unscoped.update_all(<<~SQL)
      document_number_prefix = organizations.document_number_prefix
      FROM organizations
      WHERE organizations.id = billing_entities.organization_id
          AND billing_entities.document_number_prefix != organizations.document_number_prefix
          AND billing_entities.id = organizations.id
    SQL
    # rubocop:enable Rails/SkipsModelValidations
  end

  def down
  end
end
