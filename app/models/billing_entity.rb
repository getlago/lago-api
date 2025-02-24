# frozen_string_literal: true

class BillingEntity < ApplicationRecord
  include PaperTrailTraceable
  include OrganizationTimezone
  include Currencies
  include Discard::Model

  self.discard_column = :deleted_at

  EMAIL_SETTINGS = [
    "invoice.finalized",
    "credit_note.created"
  ]

  belongs_to :organization

  has_many :applied_taxes, class_name: "BillingEntity::AppliedTax", dependent: :destroy
  has_many :customers
  has_many :fees
  has_many :invoices
  has_many :invoice_custom_section_selections, dependent: :destroy

  has_many :credit_notes, through: :invoices
  has_many :selected_invoice_custom_sections, through: :invoice_custom_section_selections, source: :invoice_custom_section
  has_many :subscriptions, through: :customers
  has_many :taxes, through: :applied_taxes
  has_many :wallets, through: :customers
  has_many :wallet_transactions, through: :wallets

  belongs_to :applied_dunning_campaign, class_name: "DunningCampaign", optional: true

  has_one_attached :logo

  DOCUMENT_NUMBERINGS = {
    per_customer: "per_customer",
    per_billing_entity: "per_billing_entity"
  }.freeze

  enum :document_numbering, DOCUMENT_NUMBERINGS

  default_scope -> { kept }

  validates :is_default,
    uniqueness: {
      conditions: -> { where(is_default: true, archived_at: nil, deleted_at: nil) },
      scope: :organization_id
    }
  validates :country, country_code: true, unless: -> { country.nil? }
  validates :default_currency, inclusion: {in: currency_list}
  validates :document_locale, language_code: true
  validates :email, email: true, if: :email?
  validates :invoice_footer, length: {maximum: 600}
  validates :document_number_prefix, length: {minimum: 1, maximum: 10}, on: :update
  validates :invoice_grace_period, numericality: {greater_than_or_equal_to: 0}
  validates :net_payment_term, numericality: {greater_than_or_equal_to: 0}
  validates :logo,
    image: {authorized_content_type: %w[image/png image/jpg image/jpeg], max_size: 800.kilobytes},
    if: :logo?
  validates :name, presence: true
  validates :timezone, timezone: true
  validates :finalize_zero_amount_invoice, inclusion: {in: [true, false]}

  validate :validate_email_settings

  after_create :generate_document_number_prefix

  private

  def generate_document_number_prefix
    update!(document_number_prefix: "#{name.first(3).upcase}-#{id.last(4).upcase}") if document_number_prefix.nil?
  end

  def validate_email_settings
    return if email_settings.all? { |v| EMAIL_SETTINGS.include?(v) }

    errors.add(:email_settings, :unsupported_value)
  end
end

# == Schema Information
#
# Table name: billing_entities
#
#  id                           :uuid             not null, primary key
#  address_line1                :string
#  address_line2                :string
#  archived_at                  :datetime
#  city                         :string
#  code                         :string           not null
#  country                      :string
#  default_currency             :string           default("USD"), not null
#  deleted_at                   :datetime
#  document_locale              :string           default("en"), not null
#  document_number_prefix       :string
#  document_numbering           :enum             default("per_customer"), not null
#  email                        :string
#  email_settings               :string           default([]), not null, is an Array
#  eu_tax_management            :boolean          default(FALSE)
#  finalize_zero_amount_invoice :boolean          default(TRUE), not null
#  invoice_footer               :text
#  invoice_grace_period         :integer          default(0), not null
#  is_default                   :boolean          default(FALSE), not null
#  legal_name                   :string
#  legal_number                 :string
#  logo                         :string
#  name                         :string           not null
#  net_payment_term             :integer          default(0), not null
#  state                        :string
#  tax_identification_number    :string
#  timezone                     :string           default("UTC"), not null
#  vat_rate                     :float            default(0.0), not null
#  zipcode                      :string
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  applied_dunning_campaign_id  :uuid
#  organization_id              :uuid             not null
#
# Indexes
#
#  index_billing_entities_on_applied_dunning_campaign_id  (applied_dunning_campaign_id)
#  index_billing_entities_on_organization_id              (organization_id)
#  unique_default_billing_entity_per_organization         (organization_id) UNIQUE WHERE ((is_default = true) AND (archived_at IS NULL) AND (deleted_at IS NULL))
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
