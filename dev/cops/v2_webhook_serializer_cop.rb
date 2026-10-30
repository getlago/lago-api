# frozen_string_literal: true

require "rubocop"

module Cops
  # A webhook cannot ask for expansions: a v2 serializer built with `webhook: true` embeds the ones
  # it declares with `webhooks: true`, which a body built without it would leave out.
  class V2WebhookSerializerCop < ::RuboCop::Cop::Base
    MSG = "Build a v2 webhook body with `webhook: true`, which embeds the expansions declared for webhooks."

    RESTRICT_ON_SEND = %i[new].freeze

    def_node_matcher :webhook_option?, <<~PATTERN
      (send _ :new ... (hash <(pair (sym :webhook) true) ...>))
    PATTERN

    def self.badge
      @badge ||= ::RuboCop::Cop::Badge.for("Lago/V2WebhookSerializer") # rubocop:disable ThreadSafety/ClassInstanceVariable
    end

    def on_send(node)
      return unless v2_serializer?(node.receiver)
      return if webhook_option?(node)

      add_offense(node)
    end

    private

    def v2_serializer?(node)
      node&.const_type? && node.const_name.match?(/\AV2::.+Serializer\z/)
    end
  end
end
