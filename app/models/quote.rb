# frozen_string_literal: true

class Quote < ApplicationRecord
  include Sequenced

  STATUSES = {
    draft: "draft",
    approved: "approved",
    voided: "voided"
  }.freeze

  ORDER_TYPES = {
    subscription_creation: "subscription_creation",
    subscription_amendment: "subscription_amendment",
    one_off: "one_off"
  }.freeze

  before_save :ensure_number

  belongs_to :organization
  belongs_to :customer
  belongs_to :subscription, optional: true
  has_many :quote_owners, dependent: :destroy
  has_many :owners, through: :quote_owners, source: :user, class_name: "User"

  enum :status, STATUSES, default: :draft, validate: true
  enum :order_type, ORDER_TYPES, instance_methods: false, validate: true

  sequenced(
    scope: ->(quote) { quote.organization.quotes },
    lock_key: ->(quote) { quote.organization_id }
  )

  private

  def ensure_number
    return if number.present?
    return if sequential_id.blank?

    time = created_at || Time.current
    formatted_sequential_id = format("%04d", sequential_id)
    self.number = "QT-#{time.strftime("%Y")}-#{formatted_sequential_id}"
  end
end

# == Schema Information
#
# Table name: quotes
# Database name: primary
#
#  id              :uuid             not null, primary key
#  number          :string           not null
#  order_type      :enum             not null
#  status          :enum             default("draft"), not null
#  version         :integer          default(1), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  customer_id     :uuid             not null
#  organization_id :uuid             not null
#  sequential_id   :integer          not null
#  subscription_id :uuid
#
# Indexes
#
#  index_quotes_on_customer_id                               (customer_id)
#  index_quotes_on_organization_number                       (organization_id,number)
#  index_quotes_on_subscription_id                           (subscription_id)
#  index_unique_quotes_on_organization_sequentialid_version  (organization_id,sequential_id,version DESC) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (customer_id => customers.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (subscription_id => subscriptions.id)
#
