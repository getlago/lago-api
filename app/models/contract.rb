# frozen_string_literal: true

# The product-catalog runtime object: what a customer signed. It can price
# through a plan, through directly attached rate cards, or both — the
# plan-less shape is native (plan_id is nullable). Legacy billing keeps its
# own `subscriptions` table; the two engines never share rows.
class Contract < ApplicationRecord
  include PaperTrailTraceable

  STATUSES = {
    pending: "pending",
    active: "active",
    terminated: "terminated",
    canceled: "canceled"
  }.freeze

  BILLING_TIMES = {
    calendar: "calendar",
    anniversary: "anniversary"
  }.freeze

  belongs_to :organization
  # with_discarded: a terminated contract must still resolve its customer and
  # plan after they are discarded — history, serializers and invoices read
  # through these associations.
  belongs_to :customer, -> { with_discarded }
  belongs_to :plan, -> { with_discarded }, optional: true
  belongs_to :catalog_plan, -> { with_discarded }, optional: true

  has_many :applied_rate_cards, class_name: "ContractRateCard"
  has_many :billing_segments

  enum :status, STATUSES, validate: true
  enum :billing_time, BILLING_TIMES, validate: true

  LIVE_STATUSES = %w[pending active].freeze

  # The live contracts for an external id: at most one per status (the partial
  # unique index is per status), so a pending replacement can coexist with the
  # active contract. Terminated and canceled siblings are history.
  scope :live, -> { where(status: LIVE_STATUSES) }

  def self.live_by_external_id(external_id)
    live.order(started_at: :desc, created_at: :desc).find_by(external_id:)
  end

  validates :external_id, presence: true

  validate :validate_started_before_ended
  validate :validate_single_plan

  # The anchor every attached rate card inherits by default: the explicit
  # anchor when one was signed, otherwise the day the contract starts — in
  # the customer's timezone, since the engine interprets dates as
  # customer-local days. A UTC truncation would shift the day around the
  # customer's midnight.
  def effective_billing_anchor_date
    billing_anchor_date || started_at&.in_time_zone(customer.applicable_timezone)&.to_date
  end

  # Authoring is pending-only: once the agreement is active (or ended) its
  # attached rate cards are signed. Unit changes on an active contract are a
  # lifecycle concern priced by the billing engine, not an authoring edit.
  def editable?
    pending?
  end

  # The currency fees bill in: the plan's when there is one, otherwise the
  # customer's (a plan-less contract), falling back to the organization default.
  def currency
    plan&.amount_currency || catalog_plan&.currency || customer.currency || organization.default_currency
  end

  # The billing lifecycle a rate card inherits when attached: it starts on the
  # contract's start day (customer-local) and shares its anchor and clock. An
  # explicit anchor overrides the default.
  def default_rate_card_lifecycle(billing_anchor_date: nil)
    {
      effective_date: started_at.in_time_zone(customer.applicable_timezone).to_date,
      billing_anchor_date: billing_anchor_date || effective_billing_anchor_date,
      next_billing_at: started_at
    }
  end

  private

  def validate_started_before_ended
    return if started_at.blank? || ended_at.blank?
    return if started_at <= ended_at

    errors.add(:ended_at, :must_be_after_started_at)
  end

  # A contract prices through a legacy plan or a catalog plan, never both; a
  # plan-less contract prices through its directly attached rate cards.
  def validate_single_plan
    has_plan = plan_id.present? || plan.present?
    has_catalog_plan = catalog_plan_id.present? || catalog_plan.present?
    return unless has_plan && has_catalog_plan

    errors.add(:base, :single_plan)
  end
end

# == Schema Information
#
# Table name: contracts
# Database name: primary
#
#  id                  :uuid             not null, primary key
#  billing_anchor_date :date
#  billing_time        :enum             default("calendar"), not null
#  canceled_at         :datetime
#  ended_at            :datetime
#  name                :string
#  started_at          :datetime
#  status              :enum             default("pending"), not null
#  terminated_at       :datetime
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  catalog_plan_id     :uuid
#  customer_id         :uuid             not null
#  external_id         :string           not null
#  organization_id     :uuid             not null
#  plan_id             :uuid
#
# Indexes
#
#  index_contracts_on_catalog_plan_id                  (catalog_plan_id)
#  index_contracts_on_customer_id                      (customer_id)
#  index_contracts_on_live_external_id                 (organization_id,external_id,status) UNIQUE WHERE (status = ANY (ARRAY['pending'::contract_status, 'active'::contract_status]))
#  index_contracts_on_organization_id                  (organization_id)
#  index_contracts_on_organization_id_and_external_id  (organization_id,external_id)
#  index_contracts_on_plan_id                          (plan_id)
#
# Foreign Keys
#
#  fk_rails_...  (catalog_plan_id => catalog_plans.id)
#  fk_rails_...  (customer_id => customers.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (plan_id => plans.id)
#
