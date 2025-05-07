# frozen_string_literal: true

class FixBillingEntityDocumentNumberingPrefix < ActiveRecord::Migration[8.0]
  class Organization < ApplicationRecord
    has_many :billing_entities
  end

  class BillingEntity < ApplicationRecord
    belongs_to :organization
  end

  def up
    # rubocop:disable Rails/SkipsModelValidations
    BillingEntity
      .joins(:organizations)
      .where("billing_entities.id = billing_entities.organization_id")
      .where("billing_entities.document_number_prefix != organizations.document_number_prefix")
      .update_all("billing_entities.document_number_prefix = organizations.document_number_prefix")
    # rubocop:enable Rails/SkipsModelValidations
  end

  def down
  end
end
