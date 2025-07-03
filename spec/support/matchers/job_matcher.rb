# frozen_string_literal: true

# This matcher ensure that a job is enqueued only after a transaction is committed to ensure no race-condition may
# happen.
RSpec::Matchers.define :have_enqueued_job_after_commit do |job|
  supports_block_expectations
  match(notify_expectation_failures: true) do |block|
    ApplicationRecord.transaction do
      block.call

      expect(job).not_to have_been_enqueued, "Expected #{job} to not have been enqueued before commit, but it was."
    end

    args = @args || []
    kwargs = @kwargs || {}

    expect(job).to have_been_enqueued.with(*args, **kwargs), "Expected #{job} to have been enqueued with #{args} and #{kwargs}, but it was not."
  end

  match_when_negated do |block|
    raise "The `have_enqueued_job_after_commit` matcher does not support negation. Use `expect { ... }.not_to have_enqueued_job` instead."
  end

  chain :with do |*args, **kwargs|
    @args = args
    @kwargs = kwargs
  end
end
