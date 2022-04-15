# frozen_string_literal: true

class Subscription < ApplicationRecord
  belongs_to :customer
  belongs_to :plan
  belongs_to :previous_subscription, class_name: 'Subscription', optional: true

  has_one :organization, through: :customer
  has_one :next_subscription, class_name: 'Subscription', foreign_key: :previous_subscription_id

  has_many :invoices
  has_many :fees

  STATUSES = [
    :pending,
    :active,
    :terminated,
    :canceled,
  ].freeze

  enum status: STATUSES

  def mark_as_active!(timestamp = Time.zone.now)
    self.started_at ||= timestamp
    active!
  end

  def mark_as_terminated!(timestamp = Time.zone.now)
    self.terminated_at ||= timestamp
    terminated!
  end

  def mark_as_canceled!
    self.canceled_at ||= Time.zone.now
    canceled!
  end

  def upgraded?
    return false unless next_subscription

    plan.amount_cents <= next_subscription.plan.amount_cents
  end
end
