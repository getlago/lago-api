# frozen_string_literal: true

class PersistedMetric < ApplicationRecord
  belongs_to :customer

  validates :external_id, presence: true
  validates :added_at, presence: true
  validates :external_subscription_id, presence: true
end
