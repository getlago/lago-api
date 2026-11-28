# frozen_string_literal: true

require "rubocop"

module Cops
  # A job enqueued inside a transaction can run before the commit and miss the data.
  # Only the calls written inside the transaction block are checked, not the methods it calls.
  class PerformLaterInTransactionCop < ::RuboCop::Cop::Base
    extend ::RuboCop::Cop::AutoCorrector

    MSG = "Do not call `%<method>s` inside a transaction: the job can run before the commit. " \
      "Use `perform_after_commit` or an `after_commit {}` block."

    RESTRICT_ON_SEND = %i[perform_later perform_all_later deliver_later].freeze
    TRANSACTION_METHODS = %i[transaction with_lock].freeze

    def self.badge
      @badge ||= ::RuboCop::Cop::Badge.for("Lago/PerformLaterInTransaction") # rubocop:disable ThreadSafety/ClassInstanceVariable
    end

    def on_send(node)
      return unless in_transaction?(node)

      add_offense(node.loc.selector, message: format(MSG, method: node.method_name)) do |corrector|
        corrector.replace(node.loc.selector, "perform_after_commit") if after_commit_replaceable?(node)
      end
    end
    alias_method :on_csend, :on_send

    private

    def in_transaction?(node)
      node.each_ancestor(:block, :numblock, :itblock, :def, :defs) do |ancestor|
        return false if ancestor.type?(:def, :defs)

        method_name = ancestor.method_name
        return false if method_name == :after_commit
        return true if TRANSACTION_METHODS.include?(method_name)
      end
      false
    end

    # `perform_after_commit` does not support configured jobs (`set(...)`), and returns no job.
    def after_commit_replaceable?(node)
      node.method?(:perform_later) && node.receiver&.const_type? && !job_read?(node)
    end

    def job_read?(node)
      node.parent&.type?(:lvasgn, :ivasgn, :op_asgn, :or_asgn, :and_asgn, :masgn, :send, :csend, :pair, :array, :return)
    end
  end
end
