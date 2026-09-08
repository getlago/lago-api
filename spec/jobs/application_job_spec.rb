# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationJob do
  let(:job_class) do
    Class.new(ApplicationJob) do
      def perform(arg1, arg2, option: "default")
      end
    end
  end

  describe ".perform_all_later" do
    let(:non_unique_job_class) do
      Class.new(ApplicationJob) do
        self.queue_adapter = :test

        def perform
        end
      end
    end

    let(:unique_job_class) do
      Class.new(ApplicationJob) do
        self.queue_adapter = :test
        unique :until_executed

        def perform
        end
      end
    end

    it "delegates to ActiveJob.perform_all_later for non-unique jobs" do
      jobs = [non_unique_job_class.new]
      allow(ActiveJob).to receive(:perform_all_later)

      described_class.perform_all_later(jobs)

      expect(ActiveJob).to have_received(:perform_all_later).with(jobs)
    end

    it "raises ArgumentError when any job has uniqueness enabled" do
      jobs = [non_unique_job_class.new, unique_job_class.new]

      expect { described_class.perform_all_later(jobs) }.to raise_error(ArgumentError, /perform_all_later is not compatible with unique jobs/)
    end
  end

  describe ".linear_delay" do
    it "grows the delay linearly with the number of executions" do
      delay = described_class.linear_delay(10)

      expect(delay.call(1)).to be_between(10, 20)
      expect(delay.call(2)).to be_between(20, 30)
      expect(delay.call(3)).to be_between(30, 40)
    end

    it "caps the delay at max_seconds" do
      delay = described_class.linear_delay(5, max_seconds: 12)

      expect(delay.call(10)).to be_between(12, 17)
    end
  end

  describe "#perform_after_commit" do
    it "performs the job after the commit" do
      ApplicationRecord.transaction do
        job_class.perform_after_commit(1, 2, option: "custom")
        expect(job_class).not_to have_been_enqueued
      end

      expect(job_class).to have_been_enqueued.with(1, 2, option: "custom")
    end
  end
end
