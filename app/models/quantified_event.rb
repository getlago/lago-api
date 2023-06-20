# frozen_string_literal: true

class QuantifiedEvent < ApplicationRecord
  include PaperTrailTraceable
  include Discard::Model
  self.discard_column = :deleted_at

  belongs_to :customer
  belongs_to :billable_metric

  has_many :events

  validates :external_id, presence: true
  validates :added_at, presence: true
  validates :external_subscription_id, presence: true

  default_scope -> { kept }
end
