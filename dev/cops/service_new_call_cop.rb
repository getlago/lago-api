# frozen_string_literal: true

require "rubocop"

module Cops
  # `Service.new(...).call` skips the middlewares that `Service.call(...)` runs (activity log, tracing).
  #
  # Flags `new(...).call` and `new(...).call!` without arguments on a constant whose name ends in
  # `Service`, and on `described_class` in a service spec. A `call` with arguments is left to
  # `Lago/ServiceCall`. A service that does not inherit `BaseService` has no class-level `call`:
  # list it in `AllowedReceivers`.
  #
  # The autocorrection is unsafe: the middlewares now run.
  class ServiceNewCallCop < ::RuboCop::Cop::Base
    extend ::RuboCop::Cop::AutoCorrector

    MSG = "Use `%<receiver>s.%<method>s(...)` instead of `%<receiver>s.new(...).%<method>s`, which skips the middlewares."
    RESTRICT_ON_SEND = %i[call call!].freeze
    SERVICE_SPEC = /_service_spec\.rb\z/

    def_node_matcher :new_call, <<~PATTERN
      (send $(send ${const (send nil? :described_class)} :new ...) {:call :call!})
    PATTERN

    def self.badge
      @badge ||= ::RuboCop::Cop::Badge.for("Lago/ServiceNewCall") # rubocop:disable ThreadSafety/ClassInstanceVariable
    end

    def on_send(node)
      return if node.arguments? || node.block_literal?

      new_call(node) do |new_node, receiver|
        next unless service?(receiver)

        message = format(MSG, receiver: receiver.source, method: node.method_name)
        add_offense(node, message:) do |corrector|
          # Rename `new` and drop the trailing call, so the arguments keep their layout.
          corrector.replace(new_node.loc.selector, node.method_name.to_s)
          corrector.remove(new_node.source_range.end.join(node.source_range.end))
        end
      end
    end

    private

    def service?(receiver)
      if receiver.const_type?
        receiver.short_name.to_s.end_with?("Service") && !allowed_receivers.include?(receiver.source.delete_prefix("::"))
      else
        SERVICE_SPEC.match?(processed_source.file_path.to_s)
      end
    end

    def allowed_receivers
      cop_config.fetch("AllowedReceivers", [])
    end
  end
end
