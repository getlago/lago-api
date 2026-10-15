# frozen_string_literal: true

# Written only by the `record_deletion()` trigger on TRACKED_TABLES, never by the application.
class RecordDeletion < ApplicationRecord
  TRACKED_TABLES = %w[fees fees_taxes invoice_subscriptions invoices_taxes credit_notes_taxes].freeze

  belongs_to :organization
end

# == Schema Information
#
# Table name: record_deletions
# Database name: primary
#
#  id              :uuid             not null, primary key
#  deleted_at      :datetime         not null
#  record_table    :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :uuid             not null
#  record_id       :uuid             not null
#
# Indexes
#
#  index_record_deletions_on_deleted_at                      (deleted_at)
#  index_record_deletions_on_organization_id_and_deleted_at  (organization_id,deleted_at)
#  index_record_deletions_on_updated_at                      (updated_at)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
