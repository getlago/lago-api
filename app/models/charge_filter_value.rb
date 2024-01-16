# frozen_string_literal: true

class ChargeFilterValue < ApplicationRecord
  include PaperTrailTraceable
  include Discard::Model
  self.discard_column = :deleted_at

  belongs_to :charge_filter
  belongs_to :billable_metric_filter

  validates :value, presence: true

  default_scope -> { kept }
end
