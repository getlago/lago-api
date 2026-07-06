# frozen_string_literal: true

require "rubocop"

module Cops
  # `expect(SomeJob).to receive(...)` stubs the job class method, so the job is never
  # enqueued and the expectation hides the real behavior. Assert enqueued jobs with
  # `have_been_enqueued`/`have_enqueued_job`, or stub with `allow(SomeJob).to receive(...)`
  # and assert with `expect(SomeJob).to have_received(...)`.
  #
  # A class counts as a job when its name ends with `Job` or when it is defined under
  # `app/jobs`. `expect(described_class)` is also checked, using the class of the
  # innermost enclosing `describe` with a constant argument.
  class NoExpectReceiveOnJobCop < ::RuboCop::Cop::Base
    MSG = "Avoid `expect(...).to receive` on job classes. Assert enqueued jobs with `have_been_enqueued`/`have_enqueued_job`, or use `allow` + `have_received`."

    RECEIVE_MATCHERS = %i[receive receive_messages receive_message_chain].freeze
    RESTRICT_ON_SEND = %i[to not_to to_not].freeze

    # Job class names derived from the Zeitwerk mapping of app/jobs, so jobs whose
    # name does not end with `Job` (e.g. DatabaseMigrations::PopulatePaymentsWithCustomerId)
    # are also detected.
    JOB_CLASS_NAMES = Dir.glob("app/jobs/**/*.rb").map do |path|
      path.delete_prefix("app/jobs/").delete_suffix(".rb").split("/").map do |segment|
        segment.split("_").map(&:capitalize).join
      end.join("::")
    end.to_set.freeze

    # Matches:
    #   expect(SendWebhookJob).to <matcher>
    #   expect(Clock::SubscriptionsBillerJob).not_to <matcher>
    #   expect(described_class).to_not <matcher>
    def_node_matcher :expect_to?, <<~PATTERN
      (send
        (send nil? :expect ${(const _ _) (send nil? :described_class)})
        {:to :not_to :to_not}
        $_
        ...)
    PATTERN

    # Matches example groups like `RSpec.describe SendWebhookJob do ... end` and
    # `describe SendWebhookJob do ... end`, capturing the described constant.
    def_node_matcher :describe_const, <<~PATTERN
      (block
        (send {nil? (const {nil? cbase} :RSpec)} :describe $(const _ _) ...)
        ...)
    PATTERN

    def self.badge
      @badge ||= ::RuboCop::Cop::Badge.for("Lago/NoExpectReceiveOnJob") # rubocop:disable ThreadSafety/ClassInstanceVariable
    end

    def on_send(node)
      subject, matcher = expect_to?(node)
      return unless matcher
      return unless receive_matcher?(matcher)
      return unless job_subject?(node, subject)

      add_offense(node)
    end

    private

    # Checks the matcher node itself and any descendant send node for a bare `receive`,
    # `receive_messages` or `receive_message_chain`, so blocks and compound matchers
    # like `have_been_enqueued.and receive(:perform_later)` are also caught.
    def receive_matcher?(matcher)
      [matcher, *matcher.each_descendant(:send)].any? do |node|
        node.send_type? && node.receiver.nil? && RECEIVE_MATCHERS.include?(node.method_name)
      end
    end

    def job_subject?(node, subject)
      if subject.const_type?
        job_const?(subject)
      else
        described_job_class?(node)
      end
    end

    # Finds the innermost enclosing `describe` with a constant argument, mirroring
    # `described_class` semantics (string describes do not change it).
    def described_job_class?(node)
      node.each_ancestor(:block) do |block|
        described = describe_const(block)
        return job_const?(described) if described
      end

      false
    end

    def job_const?(const_node)
      const_node.const_name.end_with?("Job") || JOB_CLASS_NAMES.include?(const_node.const_name)
    end
  end
end
