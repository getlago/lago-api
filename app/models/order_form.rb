# frozen_string_literal: true

class OrderForm < ApplicationRecord
  STATUSES = {
    generated: "generated",
    signed: "signed",
    expired: "expired",
    voided: "voided"
  }.freeze

  VOID_REASONS = {
    manual: "manual",
    expired: "expired",
    invalid: "invalid"
  }.freeze

  before_validation :ensure_number

  belongs_to :organization
  belongs_to :customer
  belongs_to :quote_version
  belongs_to :signed_by_user, class_name: "User", optional: true
  has_one :quote, through: :quote_version

  enum :status, STATUSES,
    default: :generated,
    validate: true
  enum :void_reason, VOID_REASONS,
    instance_methods: false,
    validate: {allow_nil: true}

  validates :billing_snapshot, presence: true
  validates :number, presence: true

  def self.ransackable_attributes(_ = nil)
    %w[number]
  end

  private

  def ensure_number
    return if number.present?
    return if quote_version.blank?

    self.number = quote_version.quote.number.sub(/\AQT-/, "OF-")
  end
end

# == Schema Information
#
# Table name: order_forms
# Database name: primary
#
#  id                :uuid             not null, primary key
#  billing_snapshot  :jsonb            not null
#  content           :text
#  expires_at        :datetime
#  legal_text        :text
#  number            :string           not null
#  signed_at         :datetime
#  status            :enum             default("generated"), not null
#  void_reason       :enum
#  voided_at         :datetime
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  customer_id       :uuid             not null
#  organization_id   :uuid             not null
#  quote_version_id  :uuid             not null
#  signed_by_user_id :uuid
#
# Indexes
#
#  index_order_forms_on_customer_id                 (customer_id)
#  index_order_forms_on_organization_id             (organization_id)
#  index_order_forms_on_organization_id_and_number  (organization_id,number)
#  index_order_forms_on_quote_version_id            (quote_version_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (customer_id => customers.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (quote_version_id => quote_versions.id)
#  fk_rails_...  (signed_by_user_id => users.id)
#
