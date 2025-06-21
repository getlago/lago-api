# frozen_string_literal: true

# This matcher ensure that a job is enqueued only after a transaction is committed to ensure no race-condition may
# happen.
RSpec::Matchers.define :enqueue_after_commit do |job|
  supports_block_expectations
  match do |block|
    ApplicationRecord.transaction do
      block.call

      expect(job).not_to have_been_enqueued
    end

    args = @args || []
    kwargs = @kwargs || {}

    expect(job).to have_been_enqueued.with(*args, **kwargs)
  end

  chain :with do |*args, **kwargs|
    @args = args
    @kwargs = kwargs
  end
end
