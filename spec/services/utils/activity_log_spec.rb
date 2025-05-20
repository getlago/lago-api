# frozen_string_literal: true

RSpec.describe Utils::ActivityLog, type: :service do
  subject(:activity_log) { described_class }

  let(:membership) { create(:membership) }
  let(:api_key) { create(:api_key) }

  before do
    allow(CurrentContext).to receive(:membership).and_return(membership.id)
    allow(CurrentContext).to receive(:api_key_id).and_return(api_key.id)
    allow(CurrentContext).to receive(:source).and_return("api")
    travel_to(Time.zone.parse("2023-03-22 12:00:00"))
  end

  describe ".produce" do
    let(:organization) { create(:organization) }
    let(:invoice) { create(:invoice, organization:) }
    let(:karafka_producer) { instance_double(WaterDrop::Producer) }

    before do
      allow(Karafka).to receive(:producer).and_return(karafka_producer)
      allow(karafka_producer).to receive(:produce_async)
    end

    context "when kafka is configured" do
      before do
        ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"] = "kafka"
        ENV["LAGO_KAFKA_ACTIVITY_LOGS_TOPIC"] = "activity_logs"
      end

      after do
        ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"] = nil
        ENV["LAGO_KAFKA_ACTIVITY_LOGS_TOPIC"] = nil
      end

      it "produces the event on kafka" do
        activity_log.produce(invoice, "invoice.created", activity_id: "activity-id") { BaseService::Result.new }

        expect(karafka_producer).to have_received(:produce_async).with(
          topic: "activity_logs",
          key: "#{organization.id}--activity-id",
          payload: {
            activity_source: "api",
            api_key_id: api_key.id,
            user_id: nil,
            activity_type: "invoice.created",
            activity_id: "activity-id",
            logged_at: Time.current.iso8601[...-1],
            created_at: Time.current.iso8601[...-1],
            resource_id: invoice.id,
            resource_type: "Invoice",
            organization_id: organization.id,
            activity_object: V1::InvoiceSerializer.new(invoice).serialize,
            activity_object_changes: {},
            external_customer_id: invoice.customer.external_id,
            external_subscription_id: nil
          }.to_json
        )
      end

      context "when the object is deleted" do
        it "does not set activity_object and activity_object_changes" do
          allow(CurrentContext).to receive(:source).and_return(nil)
          activity_log.produce(invoice, "invoice.deleted", activity_id: "activity-id") { BaseService::Result.new }

          expect(karafka_producer).to have_received(:produce_async).with(
            topic: "activity_logs",
            key: "#{organization.id}--activity-id",
            payload: {
              activity_source: "system",
              api_key_id: api_key.id,
              user_id: nil,
              activity_type: "invoice.deleted",
              activity_id: "activity-id",
              logged_at: Time.current.iso8601[...-1],
              created_at: Time.current.iso8601[...-1],
              resource_id: invoice.id,
              resource_type: "Invoice",
              organization_id: organization.id,
              activity_object: {},
              activity_object_changes: {},
              external_customer_id: invoice.customer.external_id,
              external_subscription_id: nil
            }.to_json
          )
        end
      end

      context "when the object is nil" do
        it "does not produce the event" do
          activity_log.produce(nil, "invoice.created") { BaseService::Result.new }
          expect(karafka_producer).not_to have_received(:produce_async)
        end
      end
    end

    context "when kafka is not configured" do
      before do
        ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"] = nil
        ENV["LAGO_KAFKA_ACTIVITY_LOGS_TOPIC"] = nil
      end

      it "does not produce message" do
        activity_log.produce(invoice, "invoice.created") { BaseService::Result.new }
        expect(karafka_producer).not_to have_received(:produce_async)
      end
    end
  end
end
