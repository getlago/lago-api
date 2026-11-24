# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEngineMigrations::ApiEventsCopy do
  let_it_be(:organization) { create(:organization) }

  let(:events) { [build_event(transaction_id: "tr-1"), build_event(transaction_id: "tr-2", external_subscription_id: nil)] }

  def build_event(**attributes)
    Event.new(
      organization_id: organization.id,
      external_customer_id: "cust-1",
      external_subscription_id: "sub-1",
      code: "api_calls",
      timestamp: Time.zone.at(1_763_900_000.123),
      precise_total_amount_cents: "12.5",
      properties: {"region" => "eu"},
      **attributes
    )
  end

  describe ".enqueue" do
    subject(:enqueue) { described_class.enqueue(organization:, events:) }

    context "when the organization copies its events from the API" do
      before { create(:billing_engine_migration, organization:) }

      it "enqueues one copy of the events that name a subscription" do
        expected_copies = [
          {
            "external_customer_id" => "cust-1",
            "external_subscription_id" => "sub-1",
            "transaction_id" => "tr-1",
            "code" => "api_calls",
            "timestamp" => events.first.timestamp.to_f,
            "precise_total_amount_cents" => "12.5",
            "properties" => {"region" => "eu"}
          }
        ]

        expect { enqueue }.to have_enqueued_job(BillingEngineMigrations::CopyApiEventsJob)
          .with(organization.id, satisfy { JSON.parse(it) == expected_copies })
      end

      context "when a property uses a key reserved by ActiveJob" do
        let(:properties) { {"nested" => {"_aj_globalid" => "gid://app/Customer/1"}} }
        let(:events) { [build_event(properties:)] }

        it "enqueues the copy with the property as sent" do
          expect { enqueue }.to have_enqueued_job(BillingEngineMigrations::CopyApiEventsJob)
            .with(organization.id, satisfy { JSON.parse(it).sole["properties"] == properties })
        end
      end

      context "when no event names a subscription" do
        let(:events) { [build_event(external_subscription_id: nil)] }

        it { expect { enqueue }.not_to have_enqueued_job(BillingEngineMigrations::CopyApiEventsJob) }
      end

      [
        RedisClient::CannotConnectError.new("no connection"),
        ConnectionPool::TimeoutError.new("Waited 1 sec"),
        ConnectionPool::PoolShuttingDownError.new
      ].each do |error|
        context "when the copy cannot be enqueued because of #{error.class}" do
          before do
            allow(ActiveJob::Base.queue_adapter).to receive(:enqueue).and_raise(error)
            allow(Rails.logger).to receive(:error)
          end

          it "logs the failure without raising" do
            expect { enqueue }.not_to raise_error
            expect(Rails.logger).to have_received(:error).with(/api events copy not enqueued organization_id=#{organization.id}: #{error.class}/)
          end
        end
      end
    end

    context "when the organization copies its events from the raw topic" do
      before { create(:billing_engine_migration, :copying_from_raw_topic, organization:) }

      it { expect { enqueue }.not_to have_enqueued_job(BillingEngineMigrations::CopyApiEventsJob) }
    end

    context "when the migration is paused" do
      before { create(:billing_engine_migration, organization:, status: "paused") }

      it { expect { enqueue }.not_to have_enqueued_job(BillingEngineMigrations::CopyApiEventsJob) }
    end

    context "when the organization is not migrated" do
      before { create(:billing_engine_migration) }

      it "enqueues nothing without a query once the migrations are loaded" do
        BillingEngineMigrations::Lookup.for_source(organization.id)

        statements = nil
        expect { statements = capture_sql { enqueue } }.not_to have_enqueued_job(BillingEngineMigrations::CopyApiEventsJob)
        expect(statements).to be_empty
      end
    end

    context "when the migrations cannot be loaded" do
      before do
        allow(BillingEngineMigration).to receive(:where).and_raise(ActiveRecord::ConnectionNotEstablished)
        allow(Rails.logger).to receive(:error)
      end

      it "logs the failure without raising" do
        expect { enqueue }.not_to raise_error
        expect(Rails.logger).to have_received(:error).with(/api events copy not enqueued/)
      end
    end
  end
end
