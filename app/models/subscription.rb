# frozen_string_literal: true

class Subscription < ApplicationRecord
  belongs_to :customer
  belongs_to :plan
  has_one :organization, through: :customer

  STATUSES = [
    :pending,
    :active,
    :terminated,
    :canceled
  ].freeze
  
  enum status: STATUSES

  def mark_as_active!
    self.started_at = Time.zone.now
    self.active!
  end

  def mark_as_terminated!
    self.terminated_at = Time.zone.now
    self.terminated!
  end

  def mark_as_canceled!
    self.canceled_at = Time.zone.now
    self.canceled!
  end
end
