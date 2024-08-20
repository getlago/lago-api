# frozen_string_literal: true

class ErrorDetail < ApplicationRecord
  include Discard::Model
  self.discard_column = :deleted_at
  default_scope -> { kept }

  belongs_to :owner, polymorphic: true
  belongs_to :organization

  ERROR_CODES = %w[not_provided tax_error tax_voiding_error]
  enum error_code: ERROR_CODES
end

# == Schema Information
#
# Table name: error_details
#
#  id              :uuid             not null, primary key
#  deleted_at      :datetime
#  details         :jsonb            not null
#  error_code      :integer          default("not_provided"), not null
#  owner_type      :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :uuid             not null
#  owner_id        :uuid             not null
#
# Indexes
#
#  index_error_details_on_deleted_at       (deleted_at)
#  index_error_details_on_error_code       (error_code)
#  index_error_details_on_organization_id  (organization_id)
#  index_error_details_on_owner            (owner_type,owner_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
