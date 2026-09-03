# frozen_string_literal: true

# Rows are written exclusively by the `record_deletion()` Postgres trigger installed
# on TRACKED_TABLES (see AddRecordDeletionTriggers). Nothing in the application
# inserts here, and nothing should: the trigger is what makes the feed complete for
# code paths added later.
class RecordDeletion < ApplicationRecord
  TRACKED_TABLES = %w[fees fees_taxes invoice_subscriptions invoices_taxes].freeze

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
#  idx_lookup_on_record_deletions       (organization_id,deleted_at)
#  idx_retention_on_record_deletions    (deleted_at)
#  idx_sync_cursor_on_record_deletions  (updated_at)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
