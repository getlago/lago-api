# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::ProcessContractActivityJob do
  let_it_be(:organization) { create(:organization) }

  let(:contract_activity) { create(:contract_activity, organization:, enqueued: true, enqueued_at: Time.current) }

  it_behaves_like "a configurable queue", "alerts", "SIDEKIQ_ALERTS" do
    let(:arguments) { contract_activity.id }
  end

  describe "queue routing" do
    context "when the organization is on a dedicated worker" do
      before { stub_const("Utils::DedicatedWorkerConfig::ORGANIZATION_IDS", [organization.id]) }

      it "enqueues the job and its retries on the dedicated queue" do
        expect { described_class.perform_later(contract_activity.id, 2) }
          .to have_enqueued_job(described_class).on_queue("dedicated_alerts")
      end
    end

    context "when the contract activity no longer exists" do
      it "enqueues the job on the default queue" do
        expect { described_class.perform_later(0, 2) }.to have_enqueued_job(described_class).on_queue("default")
      end
    end
  end

  describe "#perform" do
    before { allow(UsageMonitoring::ProcessContractActivityService).to receive(:call!) }

    it "processes the contract activity" do
      described_class.perform_now(contract_activity.id)

      expect(UsageMonitoring::ProcessContractActivityService).to have_received(:call!).with(contract_activity:)
      expect(described_class).not_to have_been_enqueued
    end

    context "when the contract activity no longer exists" do
      it "does nothing" do
        described_class.perform_now(0)

        expect(UsageMonitoring::ProcessContractActivityService).not_to have_received(:call!)
        expect(described_class).not_to have_been_enqueued
      end
    end

    context "when the processing fails" do
      before do
        allow(UsageMonitoring::ProcessContractActivityService).to receive(:call!).and_raise(ActiveRecord::QueryCanceled)
      end

      it "retries it with the next attempt, keeping the contract activity" do
        described_class.perform_now(contract_activity.id)

        expect(described_class).to have_been_enqueued.once.with(contract_activity.id, 2)
        expect(contract_activity.reload.enqueued).to be(true)
      end

      it "reports the error" do
        allow(Sentry).to receive(:capture_exception)

        described_class.perform_now(contract_activity.id)

        expect(Sentry).to have_received(:capture_exception).with(an_instance_of(ActiveRecord::QueryCanceled))
      end

      context "when it is the third retry" do
        it "retries it once more" do
          described_class.perform_now(contract_activity.id, 3)

          expect(described_class).to have_been_enqueued.once.with(contract_activity.id, 4)
          expect(contract_activity.reload.enqueued).to be(true)
        end
      end

      context "when it is the last retry" do
        it "deletes the contract activity and raises the error" do
          expect { described_class.perform_now(contract_activity.id, 4) }.to raise_error(ActiveRecord::QueryCanceled)

          expect(described_class).not_to have_been_enqueued
          expect(UsageMonitoring::ContractActivity.exists?(contract_activity.id)).to be(false)
        end
      end
    end
  end
end
