# frozen_string_literal: true

class FixBillingEntityDocumentNumberingPrefix < ActiveRecord::Migration[8.0]
  class Organization < ApplicationRecord
    has_many :billing_entities, foreign_key: :organization_id
  end

  class BillingEntity < ApplicationRecord
    belongs_to :organization, foreign_key: :organization_id
  end

  def up
    # Find all billing entities that need to be updated
    billing_entities = Organization
      .joins(:billing_entities)
      .where(billing_entities: { archived_at: nil })
      .where('organizations.document_number_prefix != billing_entities.document_number_prefix')
      .where('billing_entities.id = organizations.id')
      .select('billing_entities.id, organizations.document_number_prefix')

    # Update each billing entity with its organization's document number prefix
    billing_entities.each do |be|
      BillingEntity.where(id: be.id).update_all(document_number_prefix: be.document_number_prefix)
    end
  end

  def down
  end
end
