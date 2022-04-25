# frozen_string_litera: true

class Customer < ApplicationRecord
  belongs_to :organization

  has_many :subscriptions
  has_many :events
  has_many :invoices, through: :subscriptions

  validates :customer_id, presence: true, uniqueness: { scope: :organization_id }
  validates :country, country_code: true, if: :country?

  def attached_to_subscriptions?
    subscriptions.exists?
  end

  def deletable?
    !attached_to_subscriptions?
  end
end
