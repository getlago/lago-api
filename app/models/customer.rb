# frozen_string_literal: true

class Customer < ApplicationRecord
  belongs_to :organization

  has_many :subscriptions
  has_many :events
  has_many :invoices, through: :subscriptions

  validates :customer_id, presence: true, uniqueness: { scope: :organization_id }
  validates :country, country_code: true, if: :country?
  validates :vat_rate, numericality: { less_than_or_equal_to: 100, greater_than: 0 }, allow_nil: true

  def attached_to_subscriptions?
    subscriptions.exists?
  end

  def deletable?
    !attached_to_subscriptions?
  end

  def active_subscription
    subscriptions.active.order(started_at: :desc).first
  end

  def applicable_vat_rate
    return vat_rate if vat_rate.present?

    # NOTE: Uncomment after merge of organization vat_rate
    20.0 # organization.vat_rate || 0
  end
end
