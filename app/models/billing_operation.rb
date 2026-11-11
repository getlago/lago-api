# frozen_string_literal: true

class BillingOperation < ApplicationRecord
  PERIODIC_ACTIONS = {
    "renew_fixed_advance" => "Bill fixed fees when their service coverage starts",
    "close_fixed_arrears" => "Bill fixed fees when their service coverage ends",
    "close_metered_arrears" => "Bill usage when its service coverage ends",
    "renew_recurring_metered_advance" => "Bill recurring metered usage at advance renewal",
    "regroup_paid_fees" => "Group paid advance fees onto an invoice when their service coverage ends"
  }.freeze

  ACTION_TYPES = (PERIODIC_ACTIONS.keys + ["reconcile_advance_coverage"]).index_by(&:to_sym).freeze

  CAUSATION_TYPES = {
    contract_activation: "contract_activation",
    periodic_continuation: "periodic_continuation",
    contract_units_change: "contract_units_change",
    late_payment: "late_payment",
    rate_change: "rate_change",
    configuration_change: "configuration_change",
    contract_termination: "contract_termination"
  }.freeze

  CANCELLED_CAUSATION_TYPES = {
    contract_termination: "contract_termination"
  }.freeze

  belongs_to :organization
  belongs_to :customer, -> { with_discarded }
  belongs_to :contract_rate_card, -> { with_discarded }
  belongs_to :invoice, optional: true

  enum :causation_type, CAUSATION_TYPES, validate: true
  enum :cancelled_causation_type, CANCELLED_CAUSATION_TYPES, prefix: true, validate: {allow_nil: true}

  validates :action_type, inclusion: {in: ACTION_TYPES.values}
  validates :billing_at, :target_cycle_started_at, presence: true
  validate :validate_identity, if: :identity_changed?
  validate :validate_state

  scope :pending, -> { where(processed_at: nil, cancelled_at: nil) }

  def due_for_processing?(timestamp:)
    processed_at.nil? && cancelled_at.nil? && billing_at <= timestamp
  end

  private

  def validate_identity
    return if contract_rate_card_id.blank? || customer_id.blank? || organization_id.blank?

    rate_card = contract_rate_card
    linked_customer = customer
    unless rate_card
      errors.add(:contract_rate_card, :invalid)
      return
    end
    unless linked_customer
      errors.add(:customer, :invalid)
      return
    end

    errors.add(:customer, :invalid) unless rate_card.contract&.customer_id == customer_id
    errors.add(:organization, :invalid) unless rate_card.organization_id == organization_id && linked_customer.organization_id == organization_id

    assigned_invoice = invoice if invoice_id.present? || association(:invoice).loaded?
    if assigned_invoice
      errors.add(:invoice, :invalid) unless assigned_invoice.organization_id == organization_id && assigned_invoice.customer_id == customer_id
    elsif invoice_id.present?
      errors.add(:invoice, :invalid)
    end
  end

  def identity_changed?
    new_record? || will_save_change_to_organization_id? || will_save_change_to_customer_id? ||
      will_save_change_to_contract_rate_card_id? || will_save_change_to_invoice_id? ||
      (association(:invoice).loaded? && invoice.present? && invoice.new_record?)
  end

  def validate_state
    if cancelled_at.present? != cancelled_causation_type.present?
      errors.add(:cancelled_at, :invalid)
    end

    if cancelled_at.present? && processed_at.present?
      errors.add(:processed_at, :invalid)
    end
  end
end

# == Schema Information
#
# Table name: billing_operations
# Database name: primary
#
#  id                       :uuid             not null, primary key
#  action_type              :string           not null
#  billing_at               :datetime         not null
#  cancelled_at             :datetime
#  cancelled_causation_type :enum
#  causation_type           :enum             not null
#  processed_at             :datetime
#  target_cycle_started_at  :datetime         not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  contract_rate_card_id    :uuid             not null
#  customer_id              :uuid             not null
#  invoice_id               :uuid
#  organization_id          :uuid             not null
#
# Indexes
#
#  index_billing_operations_on_contract_rate_card_id      (contract_rate_card_id)
#  index_billing_operations_on_customer_id                (customer_id)
#  index_billing_operations_on_invoice_id                 (invoice_id)
#  index_billing_operations_on_organization_id            (organization_id)
#  index_pending_billing_operations_on_org_and_date       (organization_id,billing_at,id) WHERE ((processed_at IS NULL) AND (cancelled_at IS NULL))
#  index_pending_billing_operations_on_org_customer_date  (organization_id,customer_id,billing_at,id) WHERE ((processed_at IS NULL) AND (cancelled_at IS NULL))
#
# Foreign Keys
#
#  fk_rails_...  (contract_rate_card_id => contract_rate_cards.id)
#  fk_rails_...  (customer_id => customers.id)
#  fk_rails_...  (invoice_id => invoices.id)
#  fk_rails_...  (organization_id => organizations.id)
#
