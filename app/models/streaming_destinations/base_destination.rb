# frozen_string_literal: true

module StreamingDestinations
  class BaseDestination < ApplicationRecord
    include PaperTrailTraceable
    include SecretsStorable
    include SettingsStorable

    self.table_name = "streaming_destinations"

    EVENT_TYPES = %w[customer_usage.refreshed].freeze

    belongs_to :organization

    validates :event_types, presence: true
    validate :event_types_are_known
    validate :event_types_not_already_claimed

    scope :for_event, lambda { |organization, event_type|
      where(organization:).where("event_types @> ARRAY[?]::varchar[]", event_type)
    }

    private

    def event_types_are_known
      return if event_types.blank?
      return if (event_types - EVENT_TYPES).empty?

      errors.add(:event_types, :inclusion)
    end

    def event_types_not_already_claimed
      return if organization_id.nil? || event_types.blank?

      claimed = BaseDestination.where(organization_id:)
      claimed = claimed.where.not(id:) if persisted?

      return unless claimed.where("event_types && ARRAY[?]::varchar[]", event_types).exists?

      errors.add(:event_types, :already_claimed)
    end
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
