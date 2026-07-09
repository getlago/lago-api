# frozen_string_literal: true

require "rubocop"

module Cops
  # Stubbing a job class (`allow(SomeJob).to receive(...)`, `expect(SomeJob).to receive(...)`)
  # or asserting the stub (`expect(SomeJob).to have_received(...)`) hides whether the job
  # was really enqueued. Assert enqueued jobs with `have_been_enqueued`/`have_enqueued_job`.
  #
  # A class counts as a job when its name ends with `Job` or when it is defined under
  # `app/jobs`. `ActiveJob` itself is exempt because `Lago/StubPerformAllLater` directs
  # specs to stub `ActiveJob.perform_all_later` directly. `described_class` subjects are
  # also checked, using the class of the innermost enclosing `describe`/`context` with a
  # constant argument.
  class NoExpectReceiveOnJobCop < ::RuboCop::Cop::Base
    MSG = "Do not stub or set message expectations on job classes. Assert enqueued jobs with `have_been_enqueued`/`have_enqueued_job`."

    STUB_MATCHERS = %i[receive receive_messages receive_message_chain have_received].freeze
    RESTRICT_ON_SEND = %i[to not_to to_not].freeze

    jobs_root = File.expand_path("../../app/jobs", __dir__)

    # Job class names approximated from the file paths under app/jobs (a path-derived
    # constant approximation, not a full Zeitwerk mapping), so jobs whose name does not
    # end with `Job` (e.g. DatabaseMigrations::PopulatePaymentsWithCustomerId) are also
    # detected. Files under concerns/ are skipped since Rails collapses that directory.
    JOB_CLASS_NAMES = Dir.glob("#{jobs_root}/**/*.rb").filter_map do |path|
      next if path.start_with?("#{jobs_root}/concerns/")

      path.delete_prefix("#{jobs_root}/").delete_suffix(".rb").split("/").map do |segment|
        segment.split("_").map(&:capitalize).join
      end.join("::")
    end.to_set.freeze

    # Matches:
    #   expect(SendWebhookJob).to <matcher>
    #   expect(Clock::SubscriptionsBillerJob).not_to <matcher>
    #   allow(described_class).to <matcher>
    def_node_matcher :allow_or_expect_to?, <<~PATTERN
      (send
        (send nil? {:allow :expect} ${(const _ _) (send nil? :described_class)})
        {:to :not_to :to_not}
        $_
        ...)
    PATTERN

    # Matches example groups like `RSpec.describe SendWebhookJob do ... end`,
    # `describe SendWebhookJob do ... end` and `context SendWebhookJob do ... end`,
    # capturing the described constant.
    def_node_matcher :describe_const, <<~PATTERN
      (block
        (send {nil? (const {nil? cbase} :RSpec)} {:describe :context} $(const _ _) ...)
        ...)
    PATTERN

    def self.badge
      @badge ||= ::RuboCop::Cop::Badge.for("Lago/NoExpectReceiveOnJob") # rubocop:disable ThreadSafety/ClassInstanceVariable
    end

    def on_send(node)
      subject, matcher = allow_or_expect_to?(node)
      return unless matcher
      return unless stub_matcher?(matcher)
      return unless job_subject?(node, subject)

      add_offense(node)
    end

    private

    # Follows only the matcher's own chain and compound combinators to find a bare
    # `receive`, `receive_messages`, `receive_message_chain` or `have_received`: a block
    # node delegates to its send, `.and`/`.or` recurse into receiver and arguments, and
    # any other chained call recurses into its receiver. Block bodies are never
    # inspected, so a nested `expect`/`allow` inside a block does not trigger the cop.
    def stub_matcher?(node)
      if node.block_type? || node.numblock_type?
        return stub_matcher?(node.send_node)
      end

      return false unless node.send_type?

      if node.receiver.nil?
        return STUB_MATCHERS.include?(node.method_name)
      end

      if %i[and or].include?(node.method_name)
        return true if stub_matcher?(node.receiver)

        return node.arguments.any? { |arg| stub_matcher?(arg) }
      end

      stub_matcher?(node.receiver)
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
      name = const_node.const_name
      return false if name == "ActiveJob"

      name.end_with?("Job") || JOB_CLASS_NAMES.include?(name)
    end
  end
end
