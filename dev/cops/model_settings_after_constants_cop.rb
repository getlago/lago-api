# frozen_string_literal: true

require "rubocop"

module Cops
  # Layout/ClassStructure skips `self.x =` settings, so this cop places them:
  # after the includes and the constants, before any other macro or method.
  class ModelSettingsAfterConstantsCop < ::RuboCop::Cop::Base
    MSG = "Put class settings such as `self.table_name =` right after the includes and the constants."

    HEAD_METHODS = %i[include prepend extend private_constant].freeze

    def_node_matcher :setting?, <<~PATTERN
      {
        (send (self) _ _)
        ({op_asgn or_asgn and_asgn} (send (self) _) ...)
      }
    PATTERN

    def self.badge
      @badge ||= ::RuboCop::Cop::Badge.for("Lago/ModelSettingsAfterConstants") # rubocop:disable ThreadSafety/ClassInstanceVariable
    end

    def on_class(node)
      statements = body_statements(node)
      statements.each_with_index do |statement, index|
        next unless class_setting?(statement)

        add_offense(statement) if misplaced?(statements, index)
      end
    end

    private

    def misplaced?(statements, index)
      before = statements[0...index]
      after = statements[(index + 1)..]
      before.any? { |other| !head?(other) && !class_setting?(other) } || after.any? { |other| head?(other) }
    end

    def body_statements(node)
      return [] unless node.body

      node.body.begin_type? ? node.body.children : [node.body]
    end

    def class_setting?(node)
      return false unless setting?(node)
      return true unless node.send_type?

      node.setter_method?
    end

    def head?(node)
      return true if node.casgn_type?

      node.send_type? && node.receiver.nil? && HEAD_METHODS.include?(node.method_name)
    end
  end
end
