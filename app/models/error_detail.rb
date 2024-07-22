# frozen_string_literal: true

class ErrorDetail < ApplicationRecord
  include Discard::Model
  self.discard_column = :deleted_at

  belongs_to :integration, polymorphic: true, optional: true
  belongs_to :owner, polymorphic: true
end
