# frozen_string_litera: true

class Customer < ApplicationRecord
  belongs_to :organization

  has_many :subscriptions
  has_many :events
  has_many :invoices, through: :subscriptions

  validates :customer_id, presence: true

  def attached_to_subscriptions?
    subscriptions.exists?
  end

  def deletable?
    !attached_to_subscriptions?
  end
end
