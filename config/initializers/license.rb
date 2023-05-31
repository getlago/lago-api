# frozen_string_literal: true

require 'lago_utils'

License = LagoUtils::License.new(ENV['LAGO_LICENSE_URL'])

License.verify unless Rails.env.test?
