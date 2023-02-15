# frozen_string_literal: true

class Webhook < ApplicationRecord
  include RansackUuidSearch

  STATUS = %i[pending succeeded failed].freeze

  belongs_to :organization
  belongs_to :object, polymorphic: true, optional: true

  enum status: STATUS
end
