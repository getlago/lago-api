# frozen_string_literal: true

class Event < ApplicationRecord
  include Discard::Model
  self.discard_column = :deleted_at

  include CustomerTimezone
  include OrganizationTimezone

  belongs_to :organization
  belongs_to :customer, -> { with_discarded }
  belongs_to :subscription

  validates :transaction_id, presence: true, uniqueness: { scope: :subscription_id }
  validates :code, presence: true

  default_scope -> { kept }
  scope :from_datetime, ->(from_datetime) { where('events.timestamp::timestamp(0) >= ?', from_datetime) }
  scope :to_datetime, ->(to_datetime) { where('events.timestamp::timestamp(0) <= ?', to_datetime) }

  def api_client
    metadata['user_agent']
  end

  def ip_address
    metadata['ip_address']
  end
end
