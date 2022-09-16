# frozen_string_literal: true

class Wallet < ApplicationRecord
  belongs_to :customer

  has_one :organization, through: :customer

  has_many :wallet_transactions

  STATUSES = [
    :active,
    :terminated,
  ].freeze

  enum status: STATUSES

  def mark_as_terminated!(timestamp = Time.zone.now)
    self.terminated_at ||= timestamp
    terminated!
  end

  scope :expired, -> { where('wallets.expiration_date < ?', Time.current.beginning_of_day) }
end
