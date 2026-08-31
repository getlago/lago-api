# frozen_string_literal: true

module StreamingDestinations
  class KinesisDestination < BaseDestination
    # external_id lives in settings rather than secrets on purpose: AWS treats it
    # as a confused-deputy guard on the AssumeRole call, not as a credential.
    settings_accessors :stream_arn, :region, :role_arn, :external_id

    validates :stream_arn, presence: true
    validates :region, presence: true
    validates :role_arn, presence: true

    def deliver_service_class
      StreamingDestinations::Kinesis::DeliverService
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
