# frozen_string_literal: true

require "rubocop"

module Cops
  class NoDropColumnOrTableCop < ::RuboCop::Cop::Base
    MSG = "Dropping columns or tables requires a dedicated commit. " \
          "See docs/dropping_columns_and_tables.md for the full process."

    FORBIDDEN_METHODS = %i[remove_column drop_table remove_columns].freeze

    def_node_matcher :forbidden_migration_method?, <<~PATTERN
      (send nil? {#{FORBIDDEN_METHODS.map { |m| ":#{m}" }.join(" ")}} ...)
    PATTERN

    def self.badge
      @badge ||= ::RuboCop::Cop::Badge.for("Lago/NoDropColumnOrTable") # rubocop:disable ThreadSafety/ClassInstanceVariable
    end

    def on_send(node)
      return unless forbidden_migration_method?(node)

      add_offense(node)
    end
  end
end
