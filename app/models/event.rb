# frozen_string_literal: true

class Event < ApplicationRecord
  belongs_to :organization
  belongs_to :customer
  belongs_to :subscription

  validates :transaction_id, presence: true, uniqueness: { scope: :subscription_id }
  validates :code, presence: true

  scope :from_date, ->(from_date) { where('events.timestamp >= ?', from_date.beginning_of_day) }
  scope :to_date, ->(to_date) { where('events.timestamp <= ?', to_date.end_of_day) }

  def api_client
    metadata['user_agent']
  end

  def ip_address
    metadata['ip_address']
  end
end
