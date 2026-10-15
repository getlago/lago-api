# frozen_string_literal: true

module StreamingDestinations
  class BaseDestination < ApplicationRecord
    include PaperTrailTraceable
    include SecretsStorable
    include SettingsStorable

    self.table_name = "streaming_destinations"

    CURRENT_USAGE_EVENT_TYPE = "customer_usage.refreshed.v1"
    FULL_USAGE_EVENT_TYPE = "customer_full_usage.refreshed.v1"
    EVENT_TYPES = [CURRENT_USAGE_EVENT_TYPE, FULL_USAGE_EVENT_TYPE].freeze

    belongs_to :organization

    validates :event_types, presence: true
    validate :event_types_are_known
    validate :event_types_not_already_claimed

    scope :for_event, lambda { |organization, event_type|
      where(organization:, active: true).where("event_types @> ARRAY[?]::varchar[]", event_type)
    }

    def self.streams_event?(organization, event_type)
      for_event(organization, event_type).exists?
    end

    settings_accessors :customer_full_usage_excluded_plan_codes, default: []

    def event_types_for(subscription)
      return event_types unless customer_full_usage_excluded_plan_codes.include?(subscription.plan.code)

      event_types - [FULL_USAGE_EVENT_TYPE]
    end

    def producer
      raise NotImplementedError
    end

    def partition_key_for(customer:)
      nil
    end

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

      errors.add(:event_types, :taken)
    end
  end
end

# == Schema Information
#
# Table name: streaming_destinations
# Database name: primary
#
#  id              :uuid             not null, primary key
#  active          :boolean          default(FALSE), not null
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
