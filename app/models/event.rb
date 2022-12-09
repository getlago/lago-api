# frozen_string_literal: true

class Event < ApplicationRecord
  include CustomerTimezone
  include OrganizationTimezone

  belongs_to :organization
  belongs_to :customer
  belongs_to :subscription

  validates :transaction_id, presence: true, uniqueness: { scope: :subscription_id }
  validates :code, presence: true

  scope :from_datetime, ->(from_datetime) { where('events.timestamp::timestamp(0) >= ?', from_datetime) }
  scope :to_datetime, ->(to_datetime) { where('events.timestamp::timestamp(0) <= ?', to_datetime) }

  def api_client
    metadata['user_agent']
  end

  def ip_address
    metadata['ip_address']
  end
end
