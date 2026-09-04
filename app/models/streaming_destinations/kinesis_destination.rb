# frozen_string_literal: true

module StreamingDestinations
  class KinesisDestination < BaseDestination
    PARTITION_KEYS = %w[customer_external_id].freeze
    DEFAULT_PARTITION_KEY = "customer_external_id"

    settings_accessors :stream_arn, :region, :role_arn
    settings_accessors :partition_key, default: DEFAULT_PARTITION_KEY

    validates :stream_arn, presence: true
    validates :region, presence: true
    validates :role_arn, presence: true
    validates :partition_key, inclusion: {in: PARTITION_KEYS}
  end
end

# == Schema Information
#
# Table name: streaming_destinations
# Database name: primary
#
#  id              :uuid             not null, primary key
#  event_types     :string           default([]), not null, is an Array
#  secrets         :string
#  settings        :jsonb            not null
#  type            :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :uuid             not null
#
# Indexes
#
#  index_streaming_destinations_on_event_types      (event_types) USING gin
#  index_streaming_destinations_on_organization_id  (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
