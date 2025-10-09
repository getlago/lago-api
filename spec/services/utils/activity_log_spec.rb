# frozen_string_literal: true

RSpec.describe Utils::ActivityLog do
  subject(:activity_log) { described_class }

  let(:membership) { create(:membership) }
  let(:api_key) { create(:api_key) }

  let(:organization) { create(:organization) }
  let(:coupon) { create(:coupon, organization:) }
  let(:karafka_producer) { instance_double(WaterDrop::Producer) }

  let(:serialized_coupon) do
    {
      topic: "activity_logs",
      key: "#{organization.id}--activity-id",
      payload: payload.to_json
    }
  end
  let(:activity_type) { "coupon.created" }
  let(:activity_object_changes) { {} }
  let(:payload) do
    {
      activity_source: "api",
      api_key_id: api_key.id,
      user_id: nil,
      activity_type:,
      activity_id: "activity-id",
      logged_at: Time.current.iso8601[...-1],
      created_at: Time.current.iso8601[...-1],
      resource_id: coupon.id,
      resource_type: "Coupon",
      organization_id: organization.id,
      activity_object: V1::CouponSerializer.new(coupon).serialize,
      activity_object_changes:,
      external_customer_id: nil,
      external_subscription_id: nil
    }
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
    def test_produce_after_commit(&block)
      produce_result = ApplicationRecord.transaction do
        produce_result = activity_log.produce_after_commit(coupon, activity_type, activity_id: "activity-id", &block)

        expect(karafka_producer).not_to have_received(:produce_async)
        produce_result
      end

      expect(karafka_producer).to have_received(:produce_async).with(
        **serialized_coupon
      )

      produce_result
    end

    context "when kafka is configured", :kafka_configured do
      let(:result) { BaseService::Result.new }

      context "when providing a block" do
        let(:activity_type) { "coupon.updated" }
        let!(:coupon_name_before_update) { coupon.name }
        let(:activity_object_changes) { {"name" => [coupon_name_before_update, "new name"]} }

        it "produces the event on kafka after the commit" do
          produce_result = test_produce_after_commit {
            coupon.update!(name: "new name")
            result.coupon = coupon
            result
          }

          expect(produce_result).to eq(result)
        end
      end

      context "when not providing a block" do
        it "prouce the event after the commit" do
          produce_result = test_produce_after_commit

          expect(produce_result).to be_nil
        end
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

      context "when after_commit is true" do
        let(:result) { BaseService::Result.new }

        it "produces the event on kafka after the commit" do
          ApplicationRecord.transaction do
            produce_result = activity_log.produce(coupon, "coupon.created", activity_id: "activity-id", after_commit: true) { result }

            expect(produce_result).to eq(result)
            expect(karafka_producer).not_to have_received(:produce_async)
          end

          expect(karafka_producer).to have_received(:produce_async).with(
            **serialized_coupon
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

  describe "#object_serialized" do
    subject(:method_call) do
      activity_log.new(object, "object.created").send(:object_serialized)
    end

    let(:object) { create(:credit_note, organization:) }

    let(:serialized_object) do
      V1::CreditNoteSerializer.new(
        object, root_name: :credit_note, includes: Utils::ActivityLog::SERIALIZED_INCLUDED_OBJECTS[:credit_note]
      ).serialize
    end

    it "returns the serialized object" do
      expect(subject).to eq(serialized_object)
    end

    context "when the object is an invoice" do
      let(:object) { create(:invoice, organization:) }

      let(:serialized_object) do
        V1::InvoiceSerializer.new(
          object, root_name: :invoice, includes: Utils::ActivityLog::SERIALIZED_INCLUDED_OBJECTS[:invoice] - [:fees]
        ).serialize
      end

      before { create_list(:fee, 26, invoice: object) }

      it "returns the serialized invoice without fees" do
        expect(subject).to eq(serialized_object)
      end
    end
  end

  describe "#serializer_includes" do
    subject(:method_call) do
      activity_log.new(object, "object.created").send(:serializer_includes, root_name)
    end

    let(:root_name) { object.class.name.underscore.to_sym }

    context "when object is not an invoice" do
      let(:object) { create(:credit_note, organization:) }

      let(:serialized_includes) { Utils::ActivityLog::SERIALIZED_INCLUDED_OBJECTS[:credit_note] }

      it "returns the default includes for the object" do
        expect(method_call).to eq(serialized_includes)
      end
    end

    context "when object is an invoice" do
      let(:object) { create(:invoice, organization:) }

      context "when invoice has more than 25 fees" do
        let(:serializer_includes) { Utils::ActivityLog::SERIALIZED_INCLUDED_OBJECTS[:invoice] - [:fees] }

        before { create_list(:fee, 26, invoice: object) }

        it "excludes fees from the includes" do
          expect(subject).to eq(serializer_includes)
        end
      end

      context "when invoice has 25 or fewer fees" do
        let(:serializer_includes) { Utils::ActivityLog::SERIALIZED_INCLUDED_OBJECTS[:invoice] }

        before { create_list(:fee, 25, invoice: object) }

        it "includes fees in the includes" do
          expect(subject).to eq(serializer_includes)
        end
      end
    end
  end
end
