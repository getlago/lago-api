# frozen_string_literal: true

class Webhook < ApplicationRecord
  STATUS = %i[pending succeeded failed].freeze

  belongs_to :organization
  belongs_to :object, polymorphic: true

  enum status: STATUS
end
