# frozen_string_literal: true

require "active_support/tagged_logging"
require "active_support/logger"

module ActiveJob
  module Logging # :nodoc:
    extend ActiveSupport::Concern

    included do
      cattr_accessor :logger, default: ActiveSupport::Logger.new(STDOUT)
      class_attribute :log_arguments, instance_accessor: false, default: true
    end
  end
end
