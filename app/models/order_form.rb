# frozen_string_literal: true

class OrderForm < ApplicationRecord
  include Sequenced

  STATUSES = {
    generated: "generated",
    signed: "signed",
    expired: "expired",
    voided: "voided"
  }.freeze

  VOID_REASONS = {
    manual: 0,
    expired: 1,
    invalid: 2
  }.freeze

  before_save :ensure_number

  belongs_to :organization
  belongs_to :customer
  belongs_to :quote
  has_one :order

  enum :status, STATUSES,
    default: :generated,
    validate: true
  enum :void_reason, VOID_REASONS,
    instance_methods: false,
    validate: {allow_nil: true}

  scope :expirable, -> { generated.where.not(expires_at: nil).where("expires_at < ?", Time.current) }

  validates :billing_snapshot, presence: true

  def self.ransackable_attributes(_ = nil)
    %w[id number]
  end

  def self.ransackable_associations(_ = nil)
    %w[customer]
  end

  sequenced(
    scope: ->(order_form) { order_form.organization.order_forms },
    lock_key: ->(order_form) { order_form.organization_id }
  )

  private

  def ensure_number
    return if number.present?
    return if sequential_id.blank?

    time = created_at || Time.current
    formatted_sequential_id = format("%04d", sequential_id)
    self.number = "OF-#{time.strftime("%Y")}-#{formatted_sequential_id}"
  end
end

# == Schema Information
#
# Table name: order_forms
# Database name: primary
#
#  id                          :uuid             not null, primary key
#  billing_snapshot            :jsonb            not null
#  content                     :text
#  contract_uploaded_at        :datetime
#  contract_uploaded_by_user   :uuid
#  expires_at                  :datetime
#  legal_text                  :text
#  number                      :string           not null
#  signed_at                   :datetime
#  status                      :enum             default("generated"), not null
#  void_reason(Rails enum)     :integer
#  voided_at                   :datetime
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  customer_id                 :uuid             not null
#  organization_id             :uuid             not null
#  quote_id                    :uuid             not null
#  sequential_id               :integer          not null
#  signed_by_user_id           :uuid
#
# Indexes
#
#  index_order_forms_on_customer_id                       (customer_id)
#  index_order_forms_on_quote_id                          (quote_id)
#  index_unique_order_forms_on_organization_number        (organization_id,number) UNIQUE
#  index_unique_order_forms_on_organization_sequentialid  (organization_id,sequential_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (customer_id => customers.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (quote_id => quotes.id)
#  fk_rails_...  (signed_by_user_id => users.id)
#
