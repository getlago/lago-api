# frozen_string_literal: true

require "rubocop"

module Cops
  # `expect(SomeJob).to receive(...)` stubs the job class method, so the job is never
  # enqueued and the expectation hides the real behavior. Assert enqueued jobs with
  # `have_been_enqueued`/`have_enqueued_job`, or stub with `allow(SomeJob).to receive(...)`
  # and assert with `expect(SomeJob).to have_received(...)`.
  class NoExpectReceiveOnJobCop < ::RuboCop::Cop::Base
    MSG = "Avoid `expect(...).to receive` on job classes. Assert enqueued jobs with `have_been_enqueued`/`have_enqueued_job`, or use `allow` + `have_received`."

    RECEIVE_MATCHERS = %i[receive receive_messages receive_message_chain].freeze

    # Matches:
    #   expect(SendWebhookJob).to <matcher>
    #   expect(Clock::SubscriptionsBillerJob).not_to <matcher>
    #   expect(SendWebhookJob).to_not <matcher>
    def_node_matcher :expect_on_job?, <<~PATTERN
      (send
        (send nil? :expect (const _ #job_const?))
        {:to :not_to :to_not}
        $_
        ...)
    PATTERN

    def self.badge
      @badge ||= ::RuboCop::Cop::Badge.for("Lago/NoExpectReceiveOnJob") # rubocop:disable ThreadSafety/ClassInstanceVariable
    end

    def on_send(node)
      matcher = expect_on_job?(node)
      return unless matcher
      return unless receive_matcher?(matcher)

      add_offense(node)
    end

    private

    # Walks a matcher chain like `receive(:perform_later).with(anything).and_call_original`
    # down its receivers to the root send and checks it is a bare `receive`,
    # `receive_messages` or `receive_message_chain`. Block nodes are unwrapped so
    # `receive(:perform_later) { true }` is also caught.
    def receive_matcher?(matcher)
      current = matcher
      loop do
        if current.block_type? || current.numblock_type?
          current = current.send_node
        end

        break unless current.send_type? && current.receiver

        current = current.receiver
      end

      current.send_type? && RECEIVE_MATCHERS.include?(current.method_name)
    end

    def job_const?(name)
      name.to_s.end_with?("Job")
    end
  end
end
