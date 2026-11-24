# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEngineMigrations::CopyApiEventsJob do
  subject(:copy_job) { described_class }

  let(:organization_id) { SecureRandom.uuid }
  let(:events_json) { [{transaction_id: "tr-1", external_subscription_id: "sub-1"}].to_json }

  before { allow(BillingEngineMigrations::CopyApiEventsService).to receive(:call!) }

  it "copies the events" do
    copy_job.perform_now(organization_id, events_json)

    expect(BillingEngineMigrations::CopyApiEventsService).to have_received(:call!).with(organization_id:, events_json:)
  end

  context "when Kafka refuses the copies" do
    before do
      allow(BillingEngineMigrations::CopyApiEventsService).to receive(:call!).and_raise(WaterDrop::Errors::ProduceManyError.new([], "boom"))
    end

    it "retries the copy" do
      expect { copy_job.perform_now(organization_id, events_json) }
        .to have_enqueued_job(described_class).with(organization_id, events_json)
    end
  end

  context "when the copy fails" do
    let(:failure) do
      BaseService::Result.new.service_failure!(code: "shadow_organization_not_on_clickhouse_events_store", message: "boom").error
    end

    before { allow(BillingEngineMigrations::CopyApiEventsService).to receive(:call!).and_raise(failure) }

    it "raises without retrying" do
      expect { copy_job.perform_now(organization_id, events_json) }
        .to raise_error(BaseService::ServiceFailure)
        .and not_have_enqueued_job(described_class)
    end
  end
end
