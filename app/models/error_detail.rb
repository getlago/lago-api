# frozen_string_literal: true

class ErrorDetail < ApplicationRecord
  include Discard::Model
  self.discard_column = :deleted_at

  belongs_to :integration, polymorphic: true, optional: true
  belongs_to :owner, polymorphic: true
  belongs_to :organization

  ERROR_CODES = %w[not_provided]
  enum error_code: ERROR_CODES.zip(ERROR_CODES).to_h
end
