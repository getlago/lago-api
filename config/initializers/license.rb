# frozen_string_literal: true

require 'lago_utils'

unless Rails.env.test?
  License = LagoUtils::License.new(Rails.application.config.license_url)

  License.verify
end
