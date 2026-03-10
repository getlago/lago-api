# frozen_string_literal: true

class OrderForm < ApplicationRecord
  include Sequenced

  STATUSES = %i[
    draft
    published
    signed
    executed
    voided
  ].freeze

  VOID_REASONS = %i[
    manual
    expired
    superseded
    invalid
  ].freeze

  before_save :ensure_number

  belongs_to :organization
  belongs_to :customer

  has_many :catalog_references, class_name: "OrderForm::CatalogReference"
  has_many :attachments, class_name: "OrderForm::Attachment"

  enum :status, STATUSES.index_with(&:to_s), default: :draft, validation: true
  enum :void_reason, VOID_REASONS.index_with(&:to_s), instance_methods: false, validation: true

  sequenced(
    scope: ->(order_form) { order_form.organization.order_forms },
    lock_key: ->(order_form) { order_form.organization_id }
  )

  validates :number,
    presence: true,
    if: :persisted?
  validates :sequential_id,
    presence: true,
    numericality: {only_integer: true, greater_than: 0},
    if: :persisted?
  validates :version,
    presence: true,
    uniqueness: {scope: %i[organization_id sequential_id]},
    numericality: {only_integer: true, greater_than: 0},
    if: :persisted?

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
#  id                :uuid             not null, primary key
#  auto_execute      :boolean          default(FALSE), not null
#  backdated_billing :boolean          default(FALSE), not null
#  billing_payload   :jsonb            not null
#  executed_at       :datetime
#  execution_result  :jsonb
#  expires_at        :datetime
#  number            :string           not null
#  order_only        :boolean          default(FALSE), not null
#  published_at      :datetime
#  share_token       :string
#  signed_at         :datetime
#  status            :enum             default("draft"), not null
#  validated_at      :datetime
#  validation_errors :jsonb
#  version           :integer          default(1), not null
#  void_reason       :enum
#  voided_at         :datetime
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  customer_id       :uuid             not null
#  organization_id   :uuid             not null
#  sequential_id     :integer          not null
#  signed_by_user_id :uuid
#
# Indexes
#
#  index_order_forms_on_customer_id      (customer_id)
#  index_order_forms_on_organization_id  (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (customer_id => customers.id)
#  fk_rails_...  (organization_id => organizations.id)
#
