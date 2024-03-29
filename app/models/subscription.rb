# frozen_string_literal: true

class Subscription < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :customer, -> { with_discarded }
  belongs_to :plan, -> { with_discarded }
  belongs_to :previous_subscription, class_name: 'Subscription', optional: true

  has_one :organization, through: :customer
  has_many :next_subscriptions, class_name: 'Subscription', foreign_key: :previous_subscription_id
  has_many :events
  has_many :invoice_subscriptions
  has_many :invoices, through: :invoice_subscriptions
  has_many :fees

  validates :external_id, :billing_time, presence: true
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

  # NOTE: SQL query to get subscription_at into customer timezone
  def self.subscription_at_in_timezone_sql
    <<-SQL
      subscriptions.subscription_at::timestamptz AT TIME ZONE
      COALESCE(customers.timezone, organizations.timezone, 'UTC')
    SQL
  end

  # NOTE: SQL query to get subscription_at into customer timezone
  def self.ending_at_in_timezone_sql
    <<-SQL
      subscriptions.ending_at::timestamptz AT TIME ZONE
      COALESCE(customers.timezone, organizations.timezone, 'UTC')
    SQL
  end

  def mark_as_active!(timestamp = Time.current)
    self.started_at ||= timestamp
    active!
  end

  def mark_as_terminated!(timestamp = Time.current)
    self.terminated_at ||= timestamp
    terminated!
  end

  def mark_as_canceled!
    self.canceled_at ||= Time.current
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

  def trial_end_datetime
    return unless plan.has_trial?

    initial_started_at + plan.trial_period.days
  end

  def in_trial_period?
    return false unless active?
    return false if initial_started_at.future?

    trial_end_datetime.present? && trial_end_datetime.future?
  end

  def started_in_past?
    started_at.to_date < created_at.to_date
  end

  def initial_started_at
    customer.subscriptions
      .where(external_id:)
      .where.not(started_at: nil)
      .order(started_at: :asc).first&.started_at || subscription_at
  end

  def next_subscription
    next_subscriptions.not_canceled.order(created_at: :desc).first
  end

  def already_billed?
    fees.subscription_kind.any?
  end

  def starting_in_the_future?
    pending? && previous_subscription.nil?
  end

  def validate_external_id
    return unless active?
    return unless organization.subscriptions.active.exists?(external_id:)

    # NOTE: We want unique external id per organization.
    errors.add(:external_id, :value_already_exist)
  end

  def downgrade_plan_date
    return unless next_subscription
    return unless next_subscription.pending?

    ::Subscriptions::DatesService.new_instance(self, Time.current)
      .next_end_of_period.to_date + 1.day
  end

  def display_name
    name.presence || plan.name
  end

  def invoice_name
    name.presence || plan.invoice_name
  end

  # When upgrade, we want to bill one day less since date of the upgrade will be
  # included in the first invoice for the new plan
  def date_diff_with_timezone(from_datetime, to_datetime)
    number_od_days = Utils::Datetime.date_diff_with_timezone(
      from_datetime,
      to_datetime,
      customer.applicable_timezone,
    )

    return number_od_days unless terminated? && upgraded?

    number_od_days -= 1

    number_od_days.negative? ? 0 : number_od_days
  end
end
