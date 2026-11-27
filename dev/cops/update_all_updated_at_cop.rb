# frozen_string_literal: true

require "rubocop"

module Cops
  # `update_all` skips callbacks, so it does not touch `updated_at`. Set it in the same call.
  #
  # A call that leaves the record as clients see it disables the cop inline with the reason, so
  # that `updated_at` does not report a change that no API payload or webhook shows:
  # - a backfill of a value derived from data the row already has;
  # - an internal derived column, such as `search_terms`;
  # - a refresh flag that a job clears, as the job writes the change and sets `updated_at` then.
  #
  # Checks the attributes written in the call: a hash, an SQL string, or an array whose first
  # element is an SQL string. A variable or a hash with a `**` splat is not checked.
  #
  # The autocorrection adds `updated_at: Time.current` to a hash. It is unsafe: a table without
  # an `updated_at` column needs a disable comment instead.
  class UpdateAllUpdatedAtCop < ::RuboCop::Cop::Base
    extend ::RuboCop::Cop::AutoCorrector

    MSG = "Set `updated_at` in `update_all`, as it skips callbacks. Disable this cop with the reason when the record does not change."
    RESTRICT_ON_SEND = %i[update_all].freeze
    UPDATED_AT_SQL = /\bupdated_at\b/

    def self.badge
      @badge ||= ::RuboCop::Cop::Badge.for("Lago/UpdateAllUpdatedAt") # rubocop:disable ThreadSafety/ClassInstanceVariable
    end

    def on_send(node)
      updates = node.first_argument
      return if updates.nil?

      case updates.type
      when :hash
        check_hash(node, updates)
      when :str, :dstr
        add_offense(node) unless sets_updated_at_in_sql?(updates)
      when :array
        sql = updates.children.first
        add_offense(node) if sql&.type?(:str, :dstr) && !sets_updated_at_in_sql?(sql)
      end
    end
    alias_method :on_csend, :on_send

    private

    def check_hash(node, hash)
      return if hash.pairs.empty? || hash.children.any?(&:kwsplat_type?)
      return if hash.pairs.any? { |pair| pair.key.type?(:sym, :str) && pair.key.value.to_s == "updated_at" }

      add_offense(node) do |corrector|
        last_pair = hash.pairs.last
        separator = (hash.pairs.first.first_line == last_pair.last_line) ? ", " : ",\n#{" " * last_pair.loc.column}"
        corrector.insert_after(last_pair, "#{separator}updated_at: Time.current")
      end
    end

    def sets_updated_at_in_sql?(node)
      source = node.heredoc? ? node.loc.heredoc_body.source : node.source
      UPDATED_AT_SQL.match?(source)
    end
  end
end
