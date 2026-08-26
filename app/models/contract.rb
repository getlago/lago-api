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
  belongs_to :customer
  belongs_to :plan, optional: true

  has_many :applied_rate_cards, class_name: "ContractRateCard"

  enum :status, STATUSES, validate: true
  enum :billing_time, BILLING_TIMES, validate: true

  validates :external_id, presence: true

  # The anchor every attached rate card inherits by default: the explicit
  # anchor when one was signed, otherwise the day the contract starts.
  def effective_billing_anchor_date
    billing_anchor_date || (started_at || starts_at)&.to_date
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
#  ending_at           :datetime
#  name                :string
#  started_at          :datetime
#  starts_at           :datetime
#  status              :enum             default("pending"), not null
#  terminated_at       :datetime
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  customer_id         :uuid             not null
#  external_id         :string           not null
#  organization_id     :uuid             not null
#  plan_id             :uuid
#
# Indexes
#
#  index_contracts_on_customer_id                      (customer_id)
#  index_contracts_on_organization_id                  (organization_id)
#  index_contracts_on_organization_id_and_external_id  (organization_id,external_id)
#  index_contracts_on_plan_id                          (plan_id)
#
# Foreign Keys
#
#  fk_rails_...  (customer_id => customers.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (plan_id => plans.id)
#
