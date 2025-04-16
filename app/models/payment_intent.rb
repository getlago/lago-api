# frozen_string_literal: true

class PaymentIntent < ApplicationRecord
  STATUSES = [:active, :expired].freeze

  belongs_to :invoice

  enum :status, STATUSES

  attribute :expires_at, default: -> { 24.hours.from_now }

  validates :status, :expires_at, presence: true
  validates :status, uniqueness: { scope: :invoice_id }

  scope :active, -> { where('expires_at > ?', Time.current) }

  def self.awaiting_expiration
    active.where("expires_at <= ?", Time.current)
  end
end

# == Schema Information
#
# Table name: payment_intents
#
#  id          :uuid             not null, primary key
#  expires_at  :datetime         not null
#  payment_url :string
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  invoice_id  :uuid             not null
#
# Indexes
#
#  index_payment_intents_on_invoice_id  (invoice_id)
#
