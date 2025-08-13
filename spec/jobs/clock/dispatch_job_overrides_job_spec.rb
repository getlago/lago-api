# frozen_string_literal: true

require "rails_helper"

class DummyDispatchTargetJob < ApplicationJob
  queue_as :default

  def perform(organization: nil); end
end

describe Clock::DispatchJobOverridesJob, type: :job do
  subject(:job) { described_class }

  describe ".perform" do
    let(:organization) { create(:organization) }
    let(:frequency_seconds) { 60 }

    context "when the override is due to run" do
      let(:override) do
        create(
          :job_schedule_override,
          organization:,
          job_name: "DummyDispatchTargetJob",
          frequency_seconds:
        )
      end

      before { override }

      it "enqueues the target job and updates last_enqueued_at" do
        freeze_time do
          expect { job.perform_now }
            .to have_enqueued_job(DummyDispatchTargetJob).with(organization:)

          expect(override.reload.last_enqueued_at).to eq(Time.current)
        end
      end
    end

    context "when the override is NOT due yet" do
      let(:override) do
        create(
          :job_schedule_override,
          organization:,
          job_name: "DummyDispatchTargetJob",
          frequency_seconds:,
          last_enqueued_at: Time.current
        )
      end

      before { override }

      it "does not enqueue the target job" do
        expect { job.perform_now }.not_to have_enqueued_job(DummyDispatchTargetJob)
      end
    end

    context "when job_name is invalid" do
      let(:override) do
        create(:job_schedule_override, job_name: "NonExistentJobClass")
      end

      before do
        override
        allow(Rails.logger).to receive(:error)
      end

      it "does not raise an error and skips the record" do
        expect { job.perform_now }.not_to raise_error
        expect(Rails.logger).to have_received(:error).with(
          "[DispatchJobOverridesJob] Error dispatching #{override.id}: "\
          "[DispatchJobOverridesJob] Unknown job name: NonExistentJobClass"
        )
      end
    end
  end
end
