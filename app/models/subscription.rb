# frozen_string_literal: true

class Subscription < ApplicationRecord
  belongs_to :customer
  belongs_to :plan
  belongs_to :previous_subscription, class_name: 'Subscription', optional: true

  has_one :organization, through: :customer
  has_many :next_subscriptions, class_name: 'Subscription', foreign_key: :previous_subscription_id
  has_many :events
  has_many :invoice_subscriptions
  has_many :invoices, through: :invoice_subscriptions
  has_many :fees

  validates :external_id, presence: true
  validate :validate_external_id, on: :create

  STATUSES = [
    :pending,
    :active,
    :terminated,
    :canceled,
  ].freeze

  BILLING_TIME = %i[
    calendar
    anniversary
  ].freeze

  enum status: STATUSES
  enum billing_time: BILLING_TIME

  scope :starting_in_the_future, -> { pending.where(previous_subscription: nil) }

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

  def downgraded?
    return false unless next_subscription

    plan.yearly_amount_cents > next_subscription.plan.yearly_amount_cents
  end

  def trial_end_date
    return unless plan.has_trial?

    initial_started_at.to_date + plan.trial_period.days
  end

  def started_in_past?
    started_at.to_date < created_at.to_date
  end

  def initial_started_at
    customer.subscriptions
      .where(external_id: external_id)
      .where.not(started_at: nil)
      .order(started_at: :asc).first&.started_at || subscription_date
  end

  def next_subscription
    next_subscriptions.not_canceled.order(created_at: :desc).first
  end

  def fee_exists?(date)
    fees.subscription_kind.where(created_at: date.beginning_of_day..date.end_of_day).any?
  end

  def already_billed?
    fees.subscription_kind.any?
  end

  def starting_in_the_future?
    pending? && previous_subscription.nil?
  end

  def validate_external_id
    return unless active?

    # NOTE: We want unique external id per organization.
    used_ids = organization.subscriptions.active.pluck(:external_id)
    errors.add(:external_id, :value_already_exists) if used_ids&.include?(external_id)
  end

  def downgrade_plan_date
    return unless next_subscription
    return unless next_subscription.pending?

    ::Subscriptions::DatesService.new_instance(self, Time.zone.today)
      .next_end_of_period + 1.day
  end

  def display_name
    name.presence || plan.name
  end
end
