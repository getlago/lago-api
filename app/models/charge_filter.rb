# frozen_string_literal: true

class ChargeFilter < ApplicationRecord
  include PaperTrailTraceable
  include Discard::Model
  self.discard_column = :deleted_at

  belongs_to :charge

  has_many :values, class_name: 'ChargeFilterValue', dependent: :destroy

  default_scope -> { kept }
end
