# frozen_string_literal: true

class Order < ApplicationRecord
  include Sequenced

  STATUSES = {
    created: "created",
    executed: "executed"
  }.freeze

  BACKDATED_BILLING_OPTIONS = {
    generate_past_invoices: 0,
    start_without_invoices: 1
  }.freeze

  ORDER_TYPES = {
    subscription_creation: 0,
    subscription_amendment: 1,
    one_off: 2
  }.freeze

  EXECUTION_MODES = {
    execute_in_lago: 0,
    order_only: 1
  }.freeze

  before_save :ensure_number

  belongs_to :organization
  belongs_to :customer
  belongs_to :order_form
  has_one :quote, through: :order_form

  enum :status, STATUSES,
    default: :created,
    validate: true
  enum :order_type, ORDER_TYPES,
    instance_methods: false,
    validate: true
  enum :execution_mode, EXECUTION_MODES,
    instance_methods: false,
    validate: {allow_nil: true}
  enum :backdated_billing, BACKDATED_BILLING_OPTIONS,
    instance_methods: false,
    validate: {allow_nil: true}

  validates :billing_snapshot, presence: true

  sequenced(
    scope: ->(order) { order.organization.orders },
    lock_key: ->(order) { order.organization_id }
  )

  private

  def ensure_number
    return if number.present?
    return if sequential_id.blank?

    time = created_at || Time.current
    formatted_sequential_id = format("%04d", sequential_id)
    self.number = "ORD-#{time.strftime("%Y")}-#{formatted_sequential_id}"
  end
end

# == Schema Information
#
# Table name: orders
# Database name: primary
#
#  id                :uuid             not null, primary key
#  backdated_billing :integer
#  billing_snapshot  :jsonb            not null
#  currency          :string
#  executed_at       :datetime
#  execution_mode    :integer
#  execution_record  :json
#  number            :string           not null
#  order_type        :integer          not null
#  status            :enum             default("created"), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  customer_id       :uuid             not null
#  order_form_id     :uuid             not null
#  organization_id   :uuid             not null
#  sequential_id     :integer          not null
#
# Indexes
#
#  index_orders_on_customer_id                       (customer_id)
#  index_orders_on_order_form_id                     (order_form_id)
#  index_unique_orders_on_organization_number        (organization_id,number) UNIQUE
#  index_unique_orders_on_organization_sequentialid  (organization_id,sequential_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (customer_id => customers.id)
#  fk_rails_...  (order_form_id => order_forms.id)
#  fk_rails_...  (organization_id => organizations.id)
#
