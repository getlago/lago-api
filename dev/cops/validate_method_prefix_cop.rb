# frozen_string_literal: true

require "rubocop"

module Cops
  # A method passed to `validate` reads as a validation where it is defined.
  class ValidateMethodPrefixCop < ::RuboCop::Cop::Base
    MSG = "Name a method passed to `validate` with the `validate_` prefix (`validate_%<name>s`)."
    RESTRICT_ON_SEND = %i[validate].freeze

    def self.badge
      @badge ||= ::RuboCop::Cop::Badge.for("Lago/ValidateMethodPrefix") # rubocop:disable ThreadSafety/ClassInstanceVariable
    end

    def on_send(node)
      return unless node.receiver.nil?

      node.arguments.each do |argument|
        next unless argument.sym_type?
        next if argument.value.start_with?("validate_")

        add_offense(argument, message: format(MSG, name: argument.value))
      end
    end
  end
end
