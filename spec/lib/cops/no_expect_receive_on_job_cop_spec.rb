# frozen_string_literal: true

require "cop_helper"

RSpec.describe Cops::NoExpectReceiveOnJobCop, :config do
  it "registers an offense when expecting receive on a job class" do
    expect_offense(<<~RUBY)
      expect(SendWebhookJob).to receive(:perform_later)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Avoid `expect(...).to receive` on job classes. Assert enqueued jobs with `have_been_enqueued`/`have_enqueued_job`, or use `allow` + `have_received`.
    RUBY
  end

  it "registers an offense when expecting receive on a namespaced job class" do
    expect_offense(<<~RUBY)
      expect(Clock::SubscriptionsBillerJob).to receive(:perform_later)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Avoid `expect(...).to receive` on job classes. Assert enqueued jobs with `have_been_enqueued`/`have_enqueued_job`, or use `allow` + `have_received`.
    RUBY
  end

  it "registers an offense when negatively expecting receive on a job class" do
    expect_offense(<<~RUBY)
      expect(SendWebhookJob).not_to receive(:perform_later)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Avoid `expect(...).to receive` on job classes. Assert enqueued jobs with `have_been_enqueued`/`have_enqueued_job`, or use `allow` + `have_received`.
    RUBY
  end

  it "registers an offense when negatively expecting receive with to_not on a job class" do
    expect_offense(<<~RUBY)
      expect(SendWebhookJob).to_not receive(:perform_later)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Avoid `expect(...).to receive` on job classes. Assert enqueued jobs with `have_been_enqueued`/`have_enqueued_job`, or use `allow` + `have_received`.
    RUBY
  end

  it "registers an offense when expecting receive with a chained matcher on a job class" do
    expect_offense(<<~RUBY)
      expect(SendWebhookJob).to receive(:perform_later).with(anything)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Avoid `expect(...).to receive` on job classes. Assert enqueued jobs with `have_been_enqueued`/`have_enqueued_job`, or use `allow` + `have_received`.
    RUBY
  end

  it "registers an offense when expecting receive with a brace block on a job class" do
    expect_offense(<<~RUBY)
      expect(SendWebhookJob).to receive(:perform_later) { true }
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Avoid `expect(...).to receive` on job classes. Assert enqueued jobs with `have_been_enqueued`/`have_enqueued_job`, or use `allow` + `have_received`.
    RUBY
  end

  it "registers an offense when expecting receive with a chained matcher and call original on a job class" do
    expect_offense(<<~RUBY)
      expect(SendWebhookJob).to receive(:perform_later).and_call_original
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Avoid `expect(...).to receive` on job classes. Assert enqueued jobs with `have_been_enqueued`/`have_enqueued_job`, or use `allow` + `have_received`.
    RUBY
  end

  it "registers an offense when expecting receive with a do-end block on a job class" do
    expect_offense(<<~RUBY)
      expect(SendWebhookJob).to receive(:perform_later) do
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Avoid `expect(...).to receive` on job classes. Assert enqueued jobs with `have_been_enqueued`/`have_enqueued_job`, or use `allow` + `have_received`.
        true
      end
    RUBY
  end

  it "registers an offense when expecting receive with a numbered parameter block on a job class" do
    expect_offense(<<~RUBY)
      expect(SendWebhookJob).to receive(:perform_later) { _1 }
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Avoid `expect(...).to receive` on job classes. Assert enqueued jobs with `have_been_enqueued`/`have_enqueued_job`, or use `allow` + `have_received`.
    RUBY
  end

  it "registers an offense when expecting receive with a chained matcher and a block on a job class" do
    expect_offense(<<~RUBY)
      expect(SendWebhookJob).to receive(:perform_later).with(anything) { true }
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Avoid `expect(...).to receive` on job classes. Assert enqueued jobs with `have_been_enqueued`/`have_enqueued_job`, or use `allow` + `have_received`.
    RUBY
  end

  it "registers an offense when expecting receive_messages on a job class" do
    expect_offense(<<~RUBY)
      expect(SendWebhookJob).to receive_messages(perform_later: nil)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Avoid `expect(...).to receive` on job classes. Assert enqueued jobs with `have_been_enqueued`/`have_enqueued_job`, or use `allow` + `have_received`.
    RUBY
  end

  it "registers an offense when expecting receive_message_chain on a job class" do
    expect_offense(<<~RUBY)
      expect(SendWebhookJob).to receive_message_chain(:set, :perform_later)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Avoid `expect(...).to receive` on job classes. Assert enqueued jobs with `have_been_enqueued`/`have_enqueued_job`, or use `allow` + `have_received`.
    RUBY
  end

  it "does not register an offense when stubbing receive on a job class with allow" do
    expect_no_offenses(<<~RUBY)
      allow(SendWebhookJob).to receive(:perform_later)
    RUBY
  end

  it "does not register an offense when expecting have_received on a job class" do
    expect_no_offenses(<<~RUBY)
      expect(SendWebhookJob).to have_received(:perform_later)
    RUBY
  end

  it "does not register an offense when expecting have_received with a chained matcher on a job class" do
    expect_no_offenses(<<~RUBY)
      expect(SendWebhookJob).to have_received(:perform_later).with(anything)
    RUBY
  end

  it "does not register an offense when expecting have_been_enqueued on a job class" do
    expect_no_offenses(<<~RUBY)
      expect(SendWebhookJob).to have_been_enqueued
    RUBY
  end

  it "does not register an offense when expecting receive on a non-job class" do
    expect_no_offenses(<<~RUBY)
      expect(SomeService).to receive(:call)
    RUBY
  end

  it "does not register an offense when expecting receive on described_class" do
    expect_no_offenses(<<~RUBY)
      expect(described_class).to receive(:perform_later)
    RUBY
  end

  it "does not register an offense when expecting receive on a local variable" do
    expect_no_offenses(<<~RUBY)
      job = SendWebhookJob
      expect(job).to receive(:perform_later)
    RUBY
  end
end
