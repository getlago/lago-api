# frozen_string_literal: true

require 'lago'

License = Lago::License.new(Rails.application.config.license_url)

License.verify
