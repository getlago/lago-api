# frozen_string_literal: true

RSpec.describe Utils::ActivityLog, type: :service do
  subject(:activity_log) { described_class }

  let(:membership) { create(:membership) }
  let(:api_key) { create(:api_key) }

  let(:organization) { create(:organization) }
  let(:coupon) { create(:coupon, organization:) }
  let(:karafka_producer) { instance_double(WaterDrop::Producer) }

  let(:serialized_coupon) do
    {topic: "activity_logs",
     key: "#{organization.id}--activity-id",
     payload: {
       activity_source: "api",
       api_key_id: api_key.id,
       user_id: nil,
       activity_type: "coupon.created",
       activity_id: "activity-id",
       logged_at: Time.current.iso8601[...-1],
       created_at: Time.current.iso8601[...-1],
       resource_id: coupon.id,
       resource_type: "Coupon",
       organization_id: organization.id,
       activity_object: V1::CouponSerializer.new(coupon).serialize,
       activity_object_changes: {},
       external_customer_id: nil,
       external_subscription_id: nil
     }.to_json}
  end

  before do
    allow(CurrentContext).to receive(:membership).and_return(membership.id)
    allow(CurrentContext).to receive(:api_key_id).and_return(api_key.id)
    allow(CurrentContext).to receive(:source).and_return("api")
    travel_to(Time.zone.parse("2023-03-22 12:00:00"))

    allow(Karafka).to receive(:producer).and_return(karafka_producer)
    allow(karafka_producer).to receive(:produce_async)
  end

  around do |example|
    if example.metadata[:kafka_configured]
      ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"] = "kafka"
      ENV["LAGO_KAFKA_ACTIVITY_LOGS_TOPIC"] = "activity_logs"
    end
    example.run
  ensure
    ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"] = nil
    ENV["LAGO_KAFKA_ACTIVITY_LOGS_TOPIC"] = nil
  end

  describe ".produce_after_commit" do
    context "when kafka is configured", :kafka_configured do
      it "produces the event on kafka after the commit" do
        ApplicationRecord.transaction do
          activity_log.produce_after_commit(coupon, "coupon.created", activity_id: "activity-id") { BaseService::Result.new }

          expect(karafka_producer).not_to have_received(:produce_async)
        end

        expect(karafka_producer).to have_received(:produce_async).with(
          **serialized_coupon
        )
      end
    end
  end

  describe ".produce" do
    context "when kafka is configured", :kafka_configured do
      it "produces the event on kafka" do
        activity_log.produce(coupon, "coupon.created", activity_id: "activity-id") { BaseService::Result.new }

        expect(karafka_producer).to have_received(:produce_async).with(
          **serialized_coupon
        )
      end

      context "when the object is a wallet transaction" do
        let(:wallet) { create(:wallet, organization:) }
        let(:wallet_transaction) { create(:wallet_transaction, wallet:, organization:) }

        it "uses wallet as resource" do
          activity_log.produce(wallet_transaction, "wallet_transaction.created", activity_id: "activity-id") { BaseService::Result.new }

          expect(karafka_producer).to have_received(:produce_async).with(
            topic: "activity_logs",
            key: "#{organization.id}--activity-id",
            payload: {
              activity_source: "api",
              api_key_id: api_key.id,
              user_id: nil,
              activity_type: "wallet_transaction.created",
              activity_id: "activity-id",
              logged_at: Time.current.iso8601[...-1],
              created_at: Time.current.iso8601[...-1],
              resource_id: wallet.id,
              resource_type: "Wallet",
              organization_id: organization.id,
              activity_object: V1::WalletTransactionSerializer.new(wallet_transaction).serialize,
              activity_object_changes: {},
              external_customer_id: wallet.customer.external_id,
              external_subscription_id: nil
            }.to_json
          )
        end
      end

      context "when the object is deleted" do
        it "does not set activity_object_changes" do
          allow(CurrentContext).to receive(:source).and_return(nil)
          activity_log.produce(coupon, "coupon.deleted", activity_id: "activity-id") { BaseService::Result.new }

          expect(karafka_producer).to have_received(:produce_async).with(
            topic: "activity_logs",
            key: "#{organization.id}--activity-id",
            payload: {
              activity_source: "system",
              api_key_id: api_key.id,
              user_id: nil,
              activity_type: "coupon.deleted",
              activity_id: "activity-id",
              logged_at: Time.current.iso8601[...-1],
              created_at: Time.current.iso8601[...-1],
              resource_id: coupon.id,
              resource_type: "Coupon",
              organization_id: organization.id,
              activity_object: V1::CouponSerializer.new(coupon).serialize,
              activity_object_changes: {},
              external_customer_id: nil,
              external_subscription_id: nil
            }.to_json
          )
        end
      end

      context "when the object is nil" do
        it "does not produce the event" do
          activity_log.produce(nil, "coupon.created") { BaseService::Result.new }
          expect(karafka_producer).not_to have_received(:produce_async)
        end
      end

      context "when membership does not belong to the organization" do
        before do
          membership.update!(organization_id: create(:organization).id)
          allow(CurrentContext).to receive(:api_key_id).and_return(nil)
          allow(CurrentContext).to receive(:membership).and_return("organization_id/#{membership.id}")
        end

        it "does not set user_id" do
          activity_log.produce(coupon, "coupon.created", activity_id: "activity-id") { BaseService::Result.new }

          expect(karafka_producer).to have_received(:produce_async).with(
            topic: "activity_logs",
            key: "#{organization.id}--activity-id",
            payload: {
              activity_source: "api",
              api_key_id: nil,
              user_id: nil,
              activity_type: "coupon.created",
              activity_id: "activity-id",
              logged_at: Time.current.iso8601[...-1],
              created_at: Time.current.iso8601[...-1],
              resource_id: coupon.id,
              resource_type: "Coupon",
              organization_id: organization.id,
              activity_object: V1::CouponSerializer.new(coupon).serialize,
              activity_object_changes: {},
              external_customer_id: nil,
              external_subscription_id: nil
            }.to_json
          )
        end
      end
    end

    context "when kafka is not configured" do
      before do
        ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"] = nil
        ENV["LAGO_KAFKA_ACTIVITY_LOGS_TOPIC"] = nil
      end

      it "does not produce message" do
        activity_log.produce(coupon, "coupon.created") { BaseService::Result.new }
        expect(karafka_producer).not_to have_received(:produce_async)
      end
    end

    describe ".available?" do
      subject { activity_log.available? }

      context "without clickhouse" do
        before do
          ENV["LAGO_CLICKHOUSE_ENABLED"] = nil
        end

        it { is_expected.to be_falsey }
      end

      context "without kafka vars" do
        before do
          ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"] = nil
          ENV["LAGO_KAFKA_ACTIVITY_LOGS_TOPIC"] = nil
          ENV["LAGO_CLICKHOUSE_ENABLED"] = "true"
        end

        it { is_expected.to be_falsey }
      end

      context "with everything configured", :kafka_configured do
        before do
          ENV["LAGO_CLICKHOUSE_ENABLED"] = "true"
        end

        it { is_expected.to be_truthy }
      end
    end
  end
end
