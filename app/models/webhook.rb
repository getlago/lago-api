# frozen_string_literal: true

class Webhook < ApplicationRecord
  include RansackUuidSearch

  STATUS = %i[pending succeeded failed].freeze

  belongs_to :organization
  belongs_to :webhook_endpoint
  belongs_to :object, polymorphic: true, optional: true

  # TODO: Uncomment this and remove belongs_to :organization, fix all specs
  # delegate :organization, to: :webhook_endpoint

  enum status: STATUS
end
