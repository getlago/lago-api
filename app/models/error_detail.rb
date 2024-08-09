# frozen_string_literal: true

class ErrorDetail < ApplicationRecord
  include Discard::Model
  self.discard_column = :deleted_at
  default_scope -> { kept }

  belongs_to :owner, polymorphic: true
  belongs_to :organization

  ERROR_CODES = %w[not_provided tax_error]
  enum error_code: ERROR_CODES
end
