# frozen_string_literal: true

require "rubocop"

module Cops
  # V2 serializers render temporal values through `ModelSerializer#format_time` and
  # `#format_date`, which give native v2 endpoints microseconds and keep webhooks and activity
  # logs at seconds. A direct `iso8601` would pick one precision for all of them, and a raw
  # value would be encoded by ActiveSupport at milliseconds.
  #
  # Flags formatting calls, and the pairs whose key ends in `_at` or `_date` without the
  # matching formatter: `format_time` for `_at`, `format_date` for `_date`. Fields named
  # otherwise, such as `effective_from`, are left to the request spec check. Only the pairs of
  # rendered hashes are checked: not the arguments of a query (`where(deleted_at: nil)`) or a pattern.
  class V2TimestampFormatCop < ::RuboCop::Cop::Base
    CALL_MSG = "Render v2 timestamps with `format_time` or `format_date` instead of `%<method>s`."
    PAIR_MSG = "Render `%<key>s` with `%<formatter>s`."

    RESTRICT_ON_SEND = %i[iso8601 xmlschema rfc3339 strftime].freeze
    # Calls whose hash argument is rendered.
    MERGE_METHODS = %i[merge merge! deep_merge deep_merge! reverse_merge reverse_merge! with_defaults with_defaults!].freeze

    def_node_matcher :formatter_call?, <<~PATTERN
      (send nil? %1 _)
    PATTERN

    def self.badge
      @badge ||= ::RuboCop::Cop::Badge.for("Lago/V2TimestampFormat") # rubocop:disable ThreadSafety/ClassInstanceVariable
    end

    def on_send(node)
      add_offense(node, message: format(CALL_MSG, method: node.method_name))
    end
    alias_method :on_csend, :on_send

    def on_pair(node)
      return unless node.key.type?(:sym, :str) && rendered?(node.parent)

      key = node.key.value.to_s
      formatter = expected_formatter(key)
      return if formatter.nil? || formatter_call?(node.value, formatter)

      add_offense(node, message: format(PAIR_MSG, key:, formatter:))
    end

    private

    def rendered?(hash)
      # A nested hash is rendered as its outermost one is: `where(plans: {deleted_at: nil})` is not.
      hash = hash.parent.parent while hash.parent&.pair_type?
      call = hash.parent
      hash.hash_type? && !(call&.call_type? && call.arguments.include?(hash) && !MERGE_METHODS.include?(call.method_name))
    end

    def expected_formatter(key)
      if key.end_with?("_at")
        :format_time
      elsif key.end_with?("_date")
        :format_date
      end
    end
  end
end
