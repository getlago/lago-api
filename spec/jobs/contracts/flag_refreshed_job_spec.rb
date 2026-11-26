# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contracts::FlagRefreshedJob do
  subject(:flag_refreshed_job) { described_class }

  let(:organization_id) { SecureRandom.uuid }
  let(:external_contract_id) { "ctr_1" }

  it_behaves_like "a unique job" do
    let(:job_args) { [organization_id, external_contract_id] }
  end

  describe "queue" do
    context "when SIDEKIQ_ALERTS is true" do
      before { ENV["SIDEKIQ_ALERTS"] = "true" }
      after { ENV.delete("SIDEKIQ_ALERTS") }

      it "uses the alerts_high_priority queue" do
        expect { flag_refreshed_job.perform_later(organization_id, external_contract_id) }
          .to have_enqueued_job.on_queue("alerts_high_priority")
      end
    end

    context "when SIDEKIQ_ALERTS is not set" do
      before { ENV.delete("SIDEKIQ_ALERTS") }

      it "uses the default queue" do
        expect { flag_refreshed_job.perform_later(organization_id, external_contract_id) }
          .to have_enqueued_job.on_queue("default")
      end
    end
  end

  it "flags the contract as refreshed" do
    allow(Contracts::FlagRefreshedService).to receive(:call!)

    flag_refreshed_job.perform_now(organization_id, external_contract_id)

    expect(Contracts::FlagRefreshedService).to have_received(:call!).with(organization_id:, external_contract_id:)
  end
end
