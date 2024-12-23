# frozen_string_literal: true

class InboundWebhook < ApplicationRecord
  WEBHOOK_PROCESSING_WINDOW = 2.hours

  belongs_to :organization

  validates :event_type, :payload, :source, :status, presence: true

  STATUSES = {
    pending: "pending",
    processing: "processing",
    processed: "processed",
    failed: "failed"
  }

  enum :status, STATUSES

  scope :retriable, -> { reprocessable.or(old_pending) }
  scope :reprocessable, -> { processing.where("processing_at <= ?", WEBHOOK_PROCESSING_WINDOW.ago) }
  scope :old_pending, -> { pending.where("created_at <= ?", WEBHOOK_PROCESSING_WINDOW.ago) }

  def processing!
    update!(status: :processing, processing_at: Time.zone.now)
  end
end

# == Schema Information
#
# Table name: inbound_webhooks
#
#  id              :uuid             not null, primary key
#  code            :string
#  event_type      :string           not null
#  payload         :jsonb            not null
#  processing_at   :datetime
#  signature       :string
#  source          :string           not null
#  status          :string           default("pending"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :uuid             not null
#
# Indexes
#
#  index_inbound_webhooks_on_organization_id  (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#