# frozen_string_literal: true

require "rubocop"

module Cops
  # V2 serializers declare their datetimes with `timestamps`, which renders them through
  # `ModelSerializer#format_time`, and render their dates with `#format_date`: native v2 endpoints
  # get microseconds, webhooks and activity logs keep seconds. A direct `iso8601` would pick one
  # precision for all of them, and a raw value would be encoded by ActiveSupport at milliseconds.
  #
  # Flags formatting calls, the pairs whose key ends in `_at` written in a rendered hash, and the
  # pairs whose key ends in `_date` without `format_date`. Fields named otherwise, such as
  # `from_datetime`, are left to the request spec check. Only the pairs of rendered hashes are
  # checked: not the arguments of a query (`where(deleted_at: nil)`) or a pattern.
  class V2TimestampFormatCop < ::RuboCop::Cop::Base
    CALL_MSG = "Declare v2 datetimes with `timestamps` and render dates with `format_date` instead of `%<method>s`."
    DECLARE_MSG = "Declare `%<key>s` with `timestamps`."
    DATE_MSG = "Render `%<key>s` with `format_date`."

    RESTRICT_ON_SEND = %i[iso8601 xmlschema rfc3339 strftime].freeze
    # Calls whose hash argument is rendered.
    MERGE_METHODS = %i[merge merge! deep_merge deep_merge! reverse_merge reverse_merge! with_defaults with_defaults!].freeze

    def_node_matcher :format_date_call?, <<~PATTERN
      (send nil? :format_date _)
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
      if key.end_with?("_at")
        add_offense(node, message: format(DECLARE_MSG, key:))
      elsif key.end_with?("_date") && !format_date_call?(node.value)
        add_offense(node, message: format(DATE_MSG, key:))
      end
    end

    private

    def rendered?(hash)
      # A nested hash is rendered as its outermost one is: `where(plans: {deleted_at: nil})` is not.
      hash = hash.parent.parent while hash.parent&.pair_type?
      call = hash.parent
      hash.hash_type? && !(call&.call_type? && call.arguments.include?(hash) && !MERGE_METHODS.include?(call.method_name))
    end
  end
end
