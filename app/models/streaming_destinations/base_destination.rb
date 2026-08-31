# frozen_string_literal: true

module StreamingDestinations
  # NOTE: Abstract STI parent, should not be instantiated directly
  class BaseDestination < ApplicationRecord
    include PaperTrailTraceable
    include SecretsStorable
    include SettingsStorable
    include Discard::Model

    self.discard_column = :deleted_at
    default_scope -> { kept }

    self.table_name = "streaming_destinations"

    belongs_to :organization

    validates :code, uniqueness: {conditions: -> { kept }, scope: :organization_id}
    validates :name, presence: true

    # A nil event_types subscribes the destination to every event type, matching
    # WebhookEndpoint's behaviour.
    def subscribed?(event_type)
      return true if event_types.nil?

      event_types.include?(event_type)
    end

    def deliver_service_class
      raise NotImplementedError
    end
  end
end

# == Schema Information
#
# Table name: streaming_destinations
# Database name: primary
#
#  id              :uuid             not null, primary key
#  code            :string           not null
#  deleted_at      :datetime
#  event_types     :string           is an Array
#  name            :string           not null
#  secrets         :string
#  settings        :jsonb            not null
#  type            :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :uuid             not null
#
# Indexes
#
#  index_streaming_destinations_on_deleted_at                (deleted_at)
#  index_streaming_destinations_on_organization_id           (organization_id)
#  index_unique_streaming_destinations_on_organization_code  (organization_id,code) UNIQUE WHERE (deleted_at IS NULL)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
