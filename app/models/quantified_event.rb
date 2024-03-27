# frozen_string_literal: true

class QuantifiedEvent < ApplicationRecord
  include PaperTrailTraceable
  include Discard::Model
  self.discard_column = :deleted_at

  RECURRING_TOTAL_UNITS = "total_aggregated_units"

  belongs_to :organization
  belongs_to :billable_metric
  belongs_to :group, optional: true

  has_many :events

  validates :added_at, presence: true
  validates :external_subscription_id, presence: true

  default_scope -> { kept }
end
