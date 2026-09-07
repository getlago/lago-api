# frozen_string_literal: true

require "cop_helper"

RSpec.describe Cops::NoExpectReceiveOnJobCop, :config do
  it "registers an offense when expecting receive on a job class" do
    expect_offense(<<~RUBY)
      expect(SendWebhookJob).to receive(:perform_later)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Do not stub or set message expectations on job classes. Assert enqueued jobs with `have_been_enqueued`/`have_enqueued_job`.
    RUBY
  end

  it "registers an offense when expecting receive on a namespaced job class" do
    expect_offense(<<~RUBY)
      expect(Clock::SubscriptionsBillerJob).to receive(:perform_later)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Do not stub or set message expectations on job classes. Assert enqueued jobs with `have_been_enqueued`/`have_enqueued_job`.
    RUBY
  end

  it "registers an offense when negatively expecting receive on a job class" do
    expect_offense(<<~RUBY)
      expect(SendWebhookJob).not_to receive(:perform_later)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Do not stub or set message expectations on job classes. Assert enqueued jobs with `have_been_enqueued`/`have_enqueued_job`.
    RUBY
  end

  it "registers an offense when negatively expecting receive with to_not on a job class" do
    expect_offense(<<~RUBY)
      expect(SendWebhookJob).to_not receive(:perform_later)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Do not stub or set message expectations on job classes. Assert enqueued jobs with `have_been_enqueued`/`have_enqueued_job`.
    RUBY
  end

  it "registers an offense when expecting receive with a chained matcher on a job class" do
    expect_offense(<<~RUBY)
      expect(SendWebhookJob).to receive(:perform_later).with(anything)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Do not stub or set message expectations on job classes. Assert enqueued jobs with `have_been_enqueued`/`have_enqueued_job`.
    RUBY
  end

  it "registers an offense when expecting receive with a brace block on a job class" do
    expect_offense(<<~RUBY)
      expect(SendWebhookJob).to receive(:perform_later) { true }
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Do not stub or set message expectations on job classes. Assert enqueued jobs with `have_been_enqueued`/`have_enqueued_job`.
    RUBY
  end

  it "registers an offense when expecting receive with a chained matcher and call original on a job class" do
    expect_offense(<<~RUBY)
      expect(SendWebhookJob).to receive(:perform_later).and_call_original
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Do not stub or set message expectations on job classes. Assert enqueued jobs with `have_been_enqueued`/`have_enqueued_job`.
    RUBY
  end

  it "registers an offense when expecting receive with a do-end block on a job class" do
    expect_offense(<<~RUBY)
      expect(SendWebhookJob).to receive(:perform_later) do
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Do not stub or set message expectations on job classes. Assert enqueued jobs with `have_been_enqueued`/`have_enqueued_job`.
        true
      end
    RUBY
  end

  it "registers an offense when expecting receive with a numbered parameter block on a job class" do
    expect_offense(<<~RUBY)
      expect(SendWebhookJob).to receive(:perform_later) { _1 }
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Do not stub or set message expectations on job classes. Assert enqueued jobs with `have_been_enqueued`/`have_enqueued_job`.
    RUBY
  end

  it "registers an offense when expecting receive with a chained matcher and a block on a job class" do
    expect_offense(<<~RUBY)
      expect(SendWebhookJob).to receive(:perform_later).with(anything) { true }
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Do not stub or set message expectations on job classes. Assert enqueued jobs with `have_been_enqueued`/`have_enqueued_job`.
    RUBY
  end

  it "registers an offense when expecting receive_messages on a job class" do
    expect_offense(<<~RUBY)
      expect(SendWebhookJob).to receive_messages(perform_later: nil)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Do not stub or set message expectations on job classes. Assert enqueued jobs with `have_been_enqueued`/`have_enqueued_job`.
    RUBY
  end

  it "registers an offense when expecting receive_message_chain on a job class" do
    expect_offense(<<~RUBY)
      expect(SendWebhookJob).to receive_message_chain(:set, :perform_later)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Do not stub or set message expectations on job classes. Assert enqueued jobs with `have_been_enqueued`/`have_enqueued_job`.
    RUBY
  end

  it "registers an offense when expecting receive in a compound matcher on a job class" do
    expect_offense(<<~RUBY)
      expect(SendWebhookJob).to have_been_enqueued.and receive(:perform_later)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Do not stub or set message expectations on job classes. Assert enqueued jobs with `have_been_enqueued`/`have_enqueued_job`.
    RUBY
  end

  it "registers an offense when expecting receive on a job class from the app/jobs index" do
    expect_offense(<<~RUBY)
      expect(DatabaseMigrations::PopulatePaymentsWithCustomerId).to receive(:perform_later)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Do not stub or set message expectations on job classes. Assert enqueued jobs with `have_been_enqueued`/`have_enqueued_job`.
    RUBY
  end

  it "registers an offense when expecting receive on described_class inside a job describe" do
    expect_offense(<<~RUBY)
      RSpec.describe SendWebhookJob do
        it "enqueues" do
          expect(described_class).to receive(:perform_later)
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Do not stub or set message expectations on job classes. Assert enqueued jobs with `have_been_enqueued`/`have_enqueued_job`.
        end
      end
    RUBY
  end

  it "registers an offense when expecting receive on described_class inside a nested string describe" do
    expect_offense(<<~RUBY)
      RSpec.describe SendWebhookJob do
        describe "#perform" do
          it "enqueues" do
            expect(described_class).to receive(:perform_later)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Do not stub or set message expectations on job classes. Assert enqueued jobs with `have_been_enqueued`/`have_enqueued_job`.
          end
        end
      end
    RUBY
  end

  it "registers an offense when expecting receive on described_class inside a job context" do
    expect_offense(<<~RUBY)
      context SendWebhookJob do
        it "enqueues" do
          expect(described_class).to receive(:perform_later)
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Do not stub or set message expectations on job classes. Assert enqueued jobs with `have_been_enqueued`/`have_enqueued_job`.
        end
      end
    RUBY
  end

  it "registers an offense when stubbing receive on a job class with allow" do
    expect_offense(<<~RUBY)
      allow(SendWebhookJob).to receive(:perform_later)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Do not stub or set message expectations on job classes. Assert enqueued jobs with `have_been_enqueued`/`have_enqueued_job`.
    RUBY
  end

  it "registers an offense when expecting have_received on a job class" do
    expect_offense(<<~RUBY)
      expect(SendWebhookJob).to have_received(:perform_later)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Do not stub or set message expectations on job classes. Assert enqueued jobs with `have_been_enqueued`/`have_enqueued_job`.
    RUBY
  end

  it "registers an offense when negatively expecting have_received on a job class" do
    expect_offense(<<~RUBY)
      expect(SendWebhookJob).not_to have_received(:perform_later)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Do not stub or set message expectations on job classes. Assert enqueued jobs with `have_been_enqueued`/`have_enqueued_job`.
    RUBY
  end

  it "registers an offense when expecting have_received with a chained matcher on a job class" do
    expect_offense(<<~RUBY)
      expect(SendWebhookJob).to have_received(:perform_later).with(anything)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Do not stub or set message expectations on job classes. Assert enqueued jobs with `have_been_enqueued`/`have_enqueued_job`.
    RUBY
  end

  it "registers an offense when expecting have_received with a block on the matcher chain on a job class" do
    expect_offense(<<~RUBY)
      expect(SendWebhookJob).to have_received(:perform_later).with(anything) { |a| a.to_s }
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Do not stub or set message expectations on job classes. Assert enqueued jobs with `have_been_enqueued`/`have_enqueued_job`.
    RUBY
  end

  it "registers an offense when stubbing receive on described_class inside a job describe" do
    expect_offense(<<~RUBY)
      RSpec.describe SendWebhookJob do
        it "stubs" do
          allow(described_class).to receive(:perform_later)
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Do not stub or set message expectations on job classes. Assert enqueued jobs with `have_been_enqueued`/`have_enqueued_job`.
        end
      end
    RUBY
  end

  it "does not register an offense when a matcher block body stubs another object" do
    expect_no_offenses(<<~RUBY)
      expect(SendWebhookJob).to satisfy { allow(foo).to receive(:bar) }
    RUBY
  end

  it "does not register an offense when expecting have_been_enqueued on a job class" do
    expect_no_offenses(<<~RUBY)
      expect(SendWebhookJob).to have_been_enqueued
    RUBY
  end

  it "does not register an offense when stubbing receive on ActiveJob" do
    expect_no_offenses(<<~RUBY)
      allow(ActiveJob).to receive(:perform_all_later)
    RUBY
  end

  it "does not register an offense when expecting have_received on ActiveJob" do
    expect_no_offenses(<<~RUBY)
      expect(ActiveJob).to have_received(:perform_all_later).with(jobs)
    RUBY
  end

  it "does not register an offense when expecting receive on a non-job class" do
    expect_no_offenses(<<~RUBY)
      expect(SomeService).to receive(:call)
    RUBY
  end

  it "does not register an offense when expecting receive on described_class without an enclosing describe" do
    expect_no_offenses(<<~RUBY)
      expect(described_class).to receive(:perform_later)
    RUBY
  end

  it "does not register an offense when expecting receive on described_class inside a non-job describe" do
    expect_no_offenses(<<~RUBY)
      RSpec.describe SomeService do
        it "calls" do
          expect(described_class).to receive(:call)
        end
      end
    RUBY
  end

  it "does not register an offense when expecting receive on a non-job const close to an indexed job name" do
    expect_no_offenses(<<~RUBY)
      expect(PopulatePayments).to receive(:call)
    RUBY
  end

  it "does not register an offense when expecting receive on a local variable" do
    expect_no_offenses(<<~RUBY)
      job = SendWebhookJob
      expect(job).to receive(:perform_later)
    RUBY
  end
end
