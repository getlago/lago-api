# frozen_string_literal: true

class Subscription < ApplicationRecord
  belongs_to :customer
  belongs_to :plan
  belongs_to :previous_subscription, class_name: 'Subscription', optional: true

  has_one :organization, through: :customer
  has_many :next_subscriptions, class_name: 'Subscription', foreign_key: :previous_subscription_id

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

    plan.yearly_amount_cents <= next_subscription.plan.yearly_amount_cents
  end

  def trial_end_date
    return unless plan.has_trial?

    started_at.to_date + plan.trial_period.days
  end

  def next_subscription
    next_subscriptions.not_canceled.order(created_at: :desc).first
  end

  def pending_start_date
    return unless pending?

    (created_at.end_of_month + 1.day).to_date
  end
end
