# frozen_string_literal: true

require "rubocop"

module Cops
  class MigrationsIfNotExistsCop < ::RuboCop::Cop::Base
    MSG = "Use if_not_exists: true when adding schema objects in a migration so retries can resume."
    ADD_METHODS = %i[add_column add_index add_foreign_key add_check_constraint].freeze

    def self.badge
      @badge ||= ::RuboCop::Cop::Badge.for("Lago/MigrationsIfNotExists") # rubocop:disable ThreadSafety/ClassInstanceVariable
    end

    def on_send(node)
      return unless node.receiver.nil? && ADD_METHODS.include?(node.method_name)

      options = node.arguments.last
      return if options&.hash_type? && options.pairs.any? do |pair|
        pair.key.sym_type? && pair.key.value == :if_not_exists && pair.value.true_type?
      end

      add_offense(node)
    end
  end
end
