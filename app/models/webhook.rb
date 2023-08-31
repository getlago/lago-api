# frozen_string_literal: true

class Webhook < ApplicationRecord
  include RansackUuidSearch

  STATUS = %i[pending succeeded failed].freeze

  belongs_to :webhook_endpoint
  belongs_to :object, polymorphic: true, optional: true

  delegate :organization, to: :webhook_endpoint

  enum status: STATUS

  def self.ransackable_attributes(_auth_object = nil)
    %w[id webhook_type]
  end
end
