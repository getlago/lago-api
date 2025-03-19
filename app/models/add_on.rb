# frozen_string_literal: true

class AddOn < ApplicationRecord
  include PaperTrailTraceable
  include Currencies
  include IntegrationMappable
  include Discard::Model
  self.discard_column = :deleted_at

  belongs_to :organization

  has_many :applied_add_ons
  has_many :customers, through: :applied_add_ons
  has_many :fees

  has_many :applied_taxes, class_name: "AddOn::AppliedTax", dependent: :destroy
  has_many :taxes, through: :applied_taxes

  monetize :amount_cents

  validates :name, presence: true
  validates :code,
    presence: true,
    uniqueness: {conditions: -> { where(deleted_at: nil) }, scope: :organization_id}

  validates :amount_cents, numericality: {greater_than: 0}
  validates :amount_currency, inclusion: {in: currency_list}

  default_scope -> { kept }

  def self.ransackable_attributes(_auth_object = nil)
    %w[name code]
  end

  def invoice_name
    invoice_display_name.presence || name
  end
end

# == Schema Information
#
# Table name: add_ons
#
#  id                   :uuid             not null, primary key
#  organization_id      :uuid             not null
#  name                 :string           not null
#  code                 :string           not null
#  description          :string
#  amount_cents         :integer          not null
#  amount_currency      :string           not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  deleted_at           :datetime
#  invoice_display_name :string
#
# Indexes
#
#  index_add_ons_on_deleted_at                (deleted_at)
#  index_add_ons_on_organization_id           (organization_id)
#  index_add_ons_on_organization_id_and_code  (organization_id,code) UNIQUE
#
