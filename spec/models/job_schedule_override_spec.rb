# frozen_string_literal: true

require "rails_helper"

DummyDispatchTargetJob = Class.new(ApplicationJob)

RSpec.describe JobScheduleOverride, type: :model do
  subject(:job_schedule_override) { build(:job_schedule_override) }

  it { expect(described_class).to be_soft_deletable }

  it { is_expected.to belong_to(:organization) }

  it { is_expected.to validate_presence_of(:job_name) }
  it { is_expected.to validate_numericality_of(:frequency_seconds).only_integer.is_greater_than(0) }
  it { is_expected.to validate_uniqueness_of(:job_name).scoped_to(:organization_id) }

  describe "Scopes" do
    describe ".enabled" do
      subject { described_class.enabled }

      let(:enabled_override) { create(:job_schedule_override) }
      let(:disabled_override) { create(:job_schedule_override, :disabled) }

      before do
        enabled_override
        disabled_override
      end

      it { is_expected.to eq [enabled_override] }
    end
  end

  describe "#due_to_run?" do
    subject { job_schedule_override.due_to_run? }

    context "when last_enqueued_at is nil" do
      before { job_schedule_override.last_enqueued_at = nil }

      it { is_expected.to be true }
    end

    context "when last_enqueued_at is set" do
      before { job_schedule_override.last_enqueued_at = 1.hour.ago }

      context "when current time is greater than last_enqueued_at + frequency_seconds seconds" do
        before { job_schedule_override.frequency_seconds = 1_800 }

        it { is_expected.to be true }
      end

      context "when current time is less than last_enqueued_at + frequency_seconds seconds" do
        before { job_schedule_override.frequency_seconds = 3_601 }

        it { is_expected.to be false }
      end
    end

    describe "#job_klass" do
      subject { job_schedule_override.job_klass }

      context "when job_name is a valid constant" do
        before { job_schedule_override.job_name = "DummyDispatchTargetJob" }

        it { is_expected.to eq(DummyDispatchTargetJob) }
      end

      context "when job_name is not a valid constant" do
        before { job_schedule_override.job_name = "NonExistentJob" }

        it { is_expected.to be_nil }
      end
    end
  end
end
