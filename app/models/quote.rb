# frozen_string_literal: true

class Quote < ApplicationRecord
  include Sequenced

  STATUSES = {
    draft: "draft",
    approved: "approved",
    voided: "voided"
  }.freeze

  VOID_REASONS = {
    manual: 0,
    superseded: 1,
    cascade_of_expired: 2,
    cascade_of_voided: 3
  }.freeze

  before_save :ensure_number
  before_save :ensure_share_token

  belongs_to :organization
  belongs_to :customer
  has_one :order_form
  has_one :order, through: :order_form
  has_many :quote_owners, dependent: :destroy
  has_many :owners, through: :quote_owners, source: :user, class_name: "User"

  enum :status, STATUSES,
    default: :draft,
    validate: true
  enum :void_reason, VOID_REASONS,
    instance_methods: false,
    validate: {allow_nil: true}
  enum :order_type, Order::ORDER_TYPES,
    instance_methods: false,
    validate: true
  enum :execution_mode, Order::EXECUTION_MODES,
    instance_methods: false,
    validate: {allow_nil: true}
  enum :backdated_billing, Order::BACKDATED_BILLING_OPTIONS,
    instance_methods: false,
    validate: {allow_nil: true}

  validates :share_token,
    on: :update,
    presence: true,
    if: -> { draft? || approved? }

  validates :void_reason, :voided_at,
    on: :update,
    presence: true,
    if: -> { voided? }

  validates :approved_at,
    on: :update,
    presence: true,
    if: -> { approved? }

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

  def ensure_share_token
    return if voided?

    self.share_token ||= SecureRandom.uuid
  end
end

# == Schema Information
#
# Table name: quotes
# Database name: primary
#
#  id                            :uuid             not null, primary key
#  approved_at                   :datetime
#  auto_execute                  :boolean          default(FALSE), not null
#  backdated_billing(Rails enum) :integer
#  billing_items                 :jsonb
#  commercial_terms              :jsonb
#  contacts                      :jsonb
#  content                       :text
#  currency                      :string
#  description                   :text
#  execution_mode(Rails enum)    :integer
#  internal_notes                :text
#  legal_text                    :text
#  metadata                      :jsonb
#  number                        :string           not null
#  order_type(Rails enum)        :integer          not null
#  share_token                   :string
#  status                        :enum             default("draft"), not null
#  version                       :integer          default(1), not null
#  void_reason(Rails enum)       :integer
#  voided_at                     :datetime
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  customer_id                   :uuid             not null
#  organization_id               :uuid             not null
#  sequential_id                 :integer          not null
#
# Indexes
#
#  index_quotes_on_customer_id                               (customer_id)
#  index_unique_quotes_on_organization_sequentialid_version  (organization_id,sequential_id,version DESC) UNIQUE
#  index_unique_quotes_on_share_token                        (share_token) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (customer_id => customers.id)
#  fk_rails_...  (organization_id => organizations.id)
#
