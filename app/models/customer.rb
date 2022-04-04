# frozen_string_litera: true

class Customer < ApplicationRecord
  belongs_to :organization

  has_many :subscriptions
  has_many :events
  has_many :invoices, through: :subscriptions

  validates :customer_id, presence: true
end
