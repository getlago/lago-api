# frozen_string_literal: true

class GroupProperty < ApplicationRecord
  include Discard::Model
  self.discard_column = :deleted_at

  belongs_to :charge
  belongs_to :group

  validates :values, presence: true

  default_scope -> { kept }
end
