# frozen_string_literal: true

require "rubocop"

module Cops
  class MigrationsConcurrentIndexCop < ::RuboCop::Cop::Base
    MSG = "Use algorithm: :concurrently when adding an index in a migration."
    TRANSACTION_MSG = "Call disable_ddl_transaction! on the migration class when adding an index concurrently."

    def self.badge
      @badge ||= ::RuboCop::Cop::Badge.for("Lago/MigrationsConcurrentIndex") # rubocop:disable ThreadSafety/ClassInstanceVariable
    end

    def on_send(node)
      return unless node.receiver.nil? && node.method?(:add_index)

      options = node.arguments.last
      concurrent = options&.hash_type? && options.pairs.any? do |pair|
        pair.key.sym_type? && pair.key.value == :algorithm && pair.value.sym_type? && pair.value.value == :concurrently
      end
      add_offense(node) unless concurrent

      migration_class = node.each_ancestor(:class).first
      if migration_class && !ddl_transaction_disabled?(migration_class)
        add_offense(node, message: TRANSACTION_MSG)
      end
    end

    private

    def ddl_transaction_disabled?(migration_class)
      body = migration_class.body
      statements = body.begin_type? ? body.children : [body]
      statements.any? do |statement|
        statement&.send_type? && statement.receiver.nil? && statement.method?(:disable_ddl_transaction!)
      end
    end
  end
end
