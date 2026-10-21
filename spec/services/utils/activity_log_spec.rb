# frozen_string_literal: true

RSpec.describe Utils::ActivityLog, :capture_kafka_messages do
  subject(:activity_log) { described_class }

  let(:api_key) { create(:api_key) }
  let(:coupon) { create(:coupon, organization:) }
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

  let_it_be(:organization, refind: true) { create_default(:organization) }
  let_it_be(:membership, refind: true) { create(:membership) }

  before_all do
    create_default(:customer)
  end

  before do
    allow(CurrentContext).to receive(:membership).and_return(membership.id)
    allow(CurrentContext).to receive(:api_key_id).and_return(api_key.id)
    allow(CurrentContext).to receive(:source).and_return("api")
    travel_to(Time.zone.parse("2023-03-22 12:00:00"))
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
      let(:result) { Coupons::UpdateService::Result.new }

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

      context "when the object is a quote version" do
        let(:quote) { create(:quote, organization:) }
        let(:quote_version) { create(:quote_version, quote:, organization:) }

        it "uses quote as resource" do
          activity_log.produce(quote_version, "quote.approved", activity_id: "activity-id") { BaseService::Result.new }

          expect(karafka_producer).to have_received(:produce_async).with(
            topic: "activity_logs",
            key: "#{organization.id}--activity-id",
            payload: {
              activity_source: "api",
              api_key_id: api_key.id,
              user_id: nil,
              activity_type: "quote.approved",
              activity_id: "activity-id",
              logged_at: Time.current.iso8601[...-1],
              created_at: Time.current.iso8601[...-1],
              resource_id: quote.id,
              resource_type: "Quote",
              organization_id: organization.id,
              activity_object: V1::QuoteVersionSerializer.new(quote_version, includes: %i[billing_items]).serialize,
              activity_object_changes: {},
              external_customer_id: quote.customer.external_id,
              external_subscription_id: nil
            }.to_json
          )
        end
      end

      context "when the object is a payment receipt" do
        let(:payment_receipt) { create(:payment_receipt, organization:) }

        it "uses payment receipt as resource" do
          activity_log.produce(payment_receipt, "payment_receipt.created", activity_id: "activity-id") { BaseService::Result.new }

          expect(karafka_producer).to have_received(:produce_async) do |args|
            payload = JSON.parse(args[:payload])
            expect(payload).to include("resource_type" => "PaymentReceipt", "resource_id" => payment_receipt.id)
          end
        end
      end

      context "with catalog applied cards and rates" do
        let(:rate_card_rate) { create(:rate_card_rate, organization:) }
        let(:plan_rate_card) { create(:plan_rate_card, organization:) }
        let(:contract_rate_card) { create(:contract_rate_card, organization:) }

        it "serializes a rate without assuming a customer association" do
          activity_log.produce(rate_card_rate, "rate_card_rate.created")

          expect(karafka_producer).to have_received(:produce_async) do |args|
            payload = JSON.parse(args[:payload])
            expect(payload).to include("resource_type" => "RateCardRate", "external_customer_id" => nil)
            expect(payload.fetch("activity_object")).to include("rate_card_code" => rate_card_rate.rate_card.code)
          end
        end

        it "keeps the parent code in the delayed activity payload after both records are discarded" do
          rate_card = rate_card_rate.rate_card
          other_rate_card = create(:rate_card, organization:, code: "other-card")

          rate_card_rate.discard
          rate_card.discard
          delayed_rate = RateCardRate.with_discarded.find(rate_card_rate.id)

          activity_log.produce(delayed_rate, "rate_card_rate.deleted")

          expect(karafka_producer).to have_received(:produce_async) do |args|
            payload = JSON.parse(args[:payload])
            expect(payload.fetch("activity_object")).to include("rate_card_code" => rate_card.code)
            expect(payload.fetch("activity_object")).not_to include("rate_card_code" => other_rate_card.code)
          end
        end

        it "uses the applied plan card serializer without a customer association" do
          activity_log.produce(plan_rate_card, "plan_rate_card.created")

          expect(karafka_producer).to have_received(:produce_async) do |args|
            payload = JSON.parse(args[:payload])
            expect(payload).to include("resource_type" => "PlanRateCard", "external_customer_id" => nil)
            expect(payload.fetch("activity_object")).to include("lago_id" => plan_rate_card.id)
          end
        end

        it "uses the applied contract card serializer and its customer" do
          activity_log.produce(contract_rate_card, "contract_rate_card.created")

          expect(karafka_producer).to have_received(:produce_async) do |args|
            payload = JSON.parse(args[:payload])
            expect(payload).to include("resource_type" => "ContractRateCard", "external_customer_id" => contract_rate_card.contract.customer.external_id)
            expect(payload.fetch("activity_object")).to include("lago_id" => contract_rate_card.id)
          end
        end
      end

      # The v2 REST endpoints render catalog records and contracts through the same serializers, so
      # a key that a REST change adds, drops or renames fails here.
      context "when the object is a v2 record" do
        subject(:produce) { activity_log.produce(record, activity_type) { BaseService::Result.new } }

        let(:produced_payload) { JSON.parse(kafka_messages.sole[:payload], symbolize_names: true) }
        let(:timestamp) { "2023-03-22T12:00:00Z" }
        let(:product_category) do
          create(
            :product_category,
            organization:,
            name: "Compute",
            code: "compute",
            description: "Compute products",
            invoice_display_name: "Compute usage"
          )
        end
        let(:product) do
          create(
            :product,
            organization:,
            product_category:,
            billable_metric:,
            name: "API",
            code: "api",
            description: "API product",
            invoice_display_name: "API calls"
          )
        end
        let(:product_filter) do
          create(
            :product_filter,
            organization:,
            product:,
            name: "US",
            code: "us",
            description: "US traffic",
            invoice_display_name: "US calls"
          )
        end
        let(:vat) { create(:tax, organization:, name: "VAT", code: "vat", rate: 20.0, description: "French VAT") }
        let(:gst) { create(:tax, organization:, name: "GST", code: "gst", rate: 5.0, description: "Canadian GST") }
        # The V2 shape of the taxes: without applied_to_organization nor counts, with deleted_at.
        let(:vat_v2_payload) do
          {
            lago_id: vat.id,
            name: "VAT",
            code: "vat",
            rate: 20.0,
            description: "French VAT",
            created_at: timestamp,
            updated_at: timestamp,
            deleted_at: nil
          }
        end
        let(:gst_v2_payload) do
          {
            lago_id: gst.id,
            name: "GST",
            code: "gst",
            rate: 5.0,
            description: "Canadian GST",
            created_at: timestamp,
            updated_at: timestamp,
            deleted_at: nil
          }
        end

        let_it_be(:billable_metric) { create(:billable_metric, organization:, code: "api_calls") }

        context "with a catalog plan" do
          let(:record) { catalog_plan }
          let(:activity_type) { "plan.created" }
          let(:catalog_plan) do
            create(
              :catalog_plan,
              organization:,
              name: "Premium",
              invoice_display_name: "Premium plan",
              code: "premium",
              description: "Premium description",
              currency: "EUR"
            )
          end

          before do
            create(:plan_rate_card, organization:, catalog_plan:)

            create(:plan_applied_tax, :catalog_plan, organization:, catalog_plan:, tax: vat)
            create(:plan_applied_tax, :catalog_plan, organization:, catalog_plan:, tax: create(:tax, organization:, deleted_at: Time.current))
          end

          it "serializes the plan with its kept taxes, without the count of its rate cards" do
            produce

            expect(produced_payload[:activity_object]).to eq(
              lago_id: catalog_plan.id,
              name: "Premium",
              invoice_display_name: "Premium plan",
              code: "premium",
              description: "Premium description",
              currency: "EUR",
              created_at: timestamp,
              deleted_at: nil,
              taxes: [vat_v2_payload]
            )
          end

          # The plan.deleted webhook keeps the count of its rate cards, its log does not.
          context "when the plan is deleted" do
            let(:activity_type) { "plan.deleted" }

            before { catalog_plan.discard! }

            it "serializes the plan with its deletion date, without the count of its rate cards" do
              produce

              expect(produced_payload[:activity_object]).to eq(
                lago_id: catalog_plan.id,
                name: "Premium",
                invoice_display_name: "Premium plan",
                code: "premium",
                description: "Premium description",
                currency: "EUR",
                created_at: timestamp,
                deleted_at: timestamp,
                taxes: [vat_payload]
              )
            end
          end
        end

        context "with a product" do
          let(:record) { product }
          let(:activity_type) { "product.created" }

          before { create(:product_filter, organization:, product:) }

          it "serializes the product, without the count of its filters" do
            produce

            expect(produced_payload[:activity_object]).to eq(
              lago_id: product.id,
              product_category_code: "compute",
              billable_metric_code: "api_calls",
              name: "API",
              code: "api",
              description: "API product",
              invoice_display_name: "API calls",
              product_type: "metered",
              created_at: timestamp,
              updated_at: timestamp,
              deleted_at: nil
            )
          end
        end

        context "with a deleted product" do
          let(:record) { product }
          let(:activity_type) { "product.deleted" }

          before { product.discard! }

          it "serializes the product with its deletion date" do
            produce

            expect(produced_payload[:activity_object]).to eq(
              lago_id: product.id,
              product_category_code: "compute",
              billable_metric_code: "api_calls",
              name: "API",
              code: "api",
              description: "API product",
              invoice_display_name: "API calls",
              product_type: "metered",
              created_at: timestamp,
              updated_at: timestamp,
              deleted_at: timestamp
            )
          end
        end

        context "with a product category" do
          let(:record) { product_category }
          let(:activity_type) { "product_category.created" }

          before { create(:product, organization:, product_category:) }

          it "serializes the category, without the count of its products" do
            produce

            expect(produced_payload[:activity_object]).to eq(
              lago_id: product_category.id,
              name: "Compute",
              code: "compute",
              description: "Compute products",
              invoice_display_name: "Compute usage",
              created_at: timestamp,
              updated_at: timestamp,
              deleted_at: nil
            )
          end
        end

        context "with a product filter" do
          let(:record) { product_filter }
          let(:activity_type) { "product_filter.created" }
          let(:region) { create(:billable_metric_filter, billable_metric:, key: "region", values: %w[us eu]) }
          let(:cloud) { create(:billable_metric_filter, billable_metric:, key: "cloud", values: %w[aws gcp]) }

          before do
            # Values are listed by creation time.
            create(:product_filter_value, organization:, product_filter:, billable_metric_filter: region, value: "us", created_at: 2.minutes.ago)
            create(:product_filter_value, organization:, product_filter:, billable_metric_filter: cloud, value: nil, created_at: 1.minute.ago)
            create(:product_filter_value, organization:, product_filter:, billable_metric_filter: region, value: "eu", deleted_at: Time.current)
          end

          it "serializes the filter with its kept values" do
            produce

            expect(produced_payload[:activity_object]).to eq(
              lago_id: product_filter.id,
              product_code: "api",
              product_category_code: "compute",
              name: "US",
              code: "us",
              description: "US traffic",
              invoice_display_name: "US calls",
              values: [
                {key: "region", value: "us"},
                {key: "cloud", value: nil}
              ],
              created_at: timestamp,
              updated_at: timestamp,
              deleted_at: nil
            )
          end
        end

        context "with a rate card" do
          let(:record) { rate_card }
          let(:activity_type) { "rate_card.created" }
          let(:rate_card) do
            create(
              :rate_card,
              organization:,
              product:,
              product_filter:,
              name: "US API calls",
              code: "api_us",
              description: "API calls from the US",
              currency: "EUR"
            )
          end
          let(:terminated_rate) { create(:rate_card_rate, organization:, rate_card:, code: "launch", effective_from: Time.zone.parse("2023-01-01")) }
          let(:active_rate) { create(:rate_card_rate, organization:, rate_card:, code: "current", effective_from: Time.zone.parse("2023-02-01")) }
          let(:pending_rate) { create(:rate_card_rate, organization:, rate_card:, code: "next", effective_from: Time.zone.parse("2023-04-01")) }
          # As /rates lists them, the latest effective_from first.
          let(:rate_payloads) do
            [
              rate_payload(pending_rate, code: "next", effective_from: "2023-04-01T00:00:00Z", status: "pending"),
              rate_payload(active_rate, code: "current", effective_from: "2023-02-01T00:00:00Z", status: "active"),
              rate_payload(terminated_rate, code: "launch", effective_from: "2023-01-01T00:00:00Z", status: "terminated")
            ]
          end

          before do
            # Created in effective_from order, because a rate can only be appended after the active one.
            terminated_rate
            active_rate
            pending_rate
            # Discarded where it would otherwise be the active rate.
            create(:rate_card_rate, organization:, rate_card:, code: "dropped", effective_from: Time.zone.parse("2023-03-01"), deleted_at: Time.current)

            # Linked oldest first: listed by their links, the latest first.
            create(:rate_card_applied_tax, organization:, rate_card:, tax: gst, created_at: 2.minutes.ago)
            create(:rate_card_applied_tax, organization:, rate_card:, tax: vat, created_at: 1.minute.ago)
            create(:rate_card_applied_tax, organization:, rate_card:, tax: create(:tax, organization:, deleted_at: Time.current))
          end

          def rate_payload(rate, code:, effective_from:, status:)
            {
              lago_id: rate.id,
              code:,
              rate_card_code: "api_us",
              effective_from:,
              status:,
              rate_model: "standard",
              rate_properties: {amount: "10"},
              min_amount_cents: 0,
              billing_interval_count: 1,
              billing_interval_unit: "month",
              applied_pricing_unit_conversion_rate: nil,
              created_at: timestamp,
              updated_at: timestamp,
              deleted_at: nil
            }
          end

          it "serializes the card with its kept rates and its kept taxes" do
            produce

            expect(produced_payload[:activity_object]).to eq(
              lago_id: rate_card.id,
              product_code: "api",
              product_filter_code: "us",
              name: "US API calls",
              code: "api_us",
              description: "API calls from the US",
              currency: "EUR",
              billing_timing: "arrears",
              proration: false,
              display_on_invoice: true,
              regroup_paid_fees: nil,
              applied_pricing_unit_code: nil,
              created_at: timestamp,
              updated_at: timestamp,
              deleted_at: nil,
              taxes: [vat_v2_payload, gst_v2_payload],
              rates: rate_payloads
            )
          end

          context "when a rate is added" do
            subject(:produce) do
              activity_log.produce(rate_card, "rate_card.updated") do
                added_rate
                BaseService::Result.new
              end
            end

            let(:added_rate) { create(:rate_card_rate, organization:, rate_card:, code: "later", effective_from: Time.zone.parse("2023-05-01")) }

            it "logs the rates as the only change" do
              produce

              expect(produced_payload[:activity_object_changes]).to eq(
                rates: [
                  rate_payloads,
                  [
                    rate_payload(added_rate, code: "later", effective_from: "2023-05-01T00:00:00Z", status: "pending"),
                    *rate_payloads
                  ]
                ]
              )
            end
          end
        end

        context "with a contract" do
          let(:record) { contract }
          let(:activity_type) { "contract.created" }
          let(:customer) { create(:customer, organization:, external_id: "acme") }
          let(:contract) do
            create(
              :contract,
              organization:,
              customer:,
              external_id: "acme-2023",
              name: "Acme 2023",
              purchase_order_number: "PO-42",
              started_at: Time.current
            )
          end

          before { create(:contract_rate_card, organization:, contract:) }

          it "serializes the contract, without the count of its rate cards" do
            produce

            expect(produced_payload[:activity_object]).to eq(
              lago_id: contract.id,
              external_id: "acme-2023",
              lago_customer_id: customer.id,
              external_customer_id: "acme",
              name: "Acme 2023",
              plan_code: nil,
              status: "active",
              billing_time: "calendar",
              consolidate_invoice: true,
              purchase_order_number: "PO-42",
              billing_anchor_date: nil,
              effective_billing_anchor_date: "2023-03-22",
              started_at: timestamp,
              ended_at: nil,
              terminated_at: nil,
              canceled_at: nil,
              skip_invoice_custom_sections: false,
              created_at: timestamp,
              updated_at: timestamp
            )
          end
        end

        context "with a contract applied rate card" do
          let(:record) { contract_rate_card }
          let(:activity_type) { "contract_rate_card.created" }
          let(:contract_rate_card) do
            create(
              :contract_rate_card,
              organization:,
              contract: create(:contract, organization:, external_id: "acme-2023"),
              rate_card: create(:rate_card, organization:, code: "api_eu")
            )
          end

          before { create(:rate_phase, organization:, plan_rate_card: nil, contract_rate_card:) }

          it "serializes the card, without the count of its rate phases" do
            produce

            expect(produced_payload[:activity_object]).to eq(
              lago_id: contract_rate_card.id,
              external_contract_id: "acme-2023",
              rate_card_code: "api_eu",
              units: nil,
              effective_date: "2023-03-22",
              billing_anchor_date: "2023-03-22",
              next_billing_at: timestamp,
              created_at: timestamp,
              updated_at: timestamp,
              deleted_at: nil
            )
          end
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

      [
        {exception: WaterDrop::Errors::ProduceError, message: "#<Rdkafka::RdkafkaError: Local: Unknown topic (unknown_topic)>", level: :error},
        {exception: WaterDrop::Errors::MessageInvalidError, message: "Message is too large", level: :warning}
      ].each do |error_context|
        exception = error_context[:exception]
        message = error_context[:message]
        level = error_context[:level]
        context "when producer raises #{exception}" do
          subject(:produce) { activity_log.produce(coupon, "coupon.created", activity_id: "activity-id") { result } }

          let(:result) { BaseService::Result.new }

          before do
            allow(karafka_producer).to receive(:produce_async).and_raise(exception.new(message))
          end

          context "when sentry is configured", :sentry do
            it "captures the exception with the #{level} level and returns false" do
              expect(produce).to be result
              expect(sentry_events).to include_sentry_event(exception: exception, message: message)
              expect(sentry_events.last.level).to eq(level)
            end
          end

          context "when sentry is not configured" do
            it "re-raises the error" do
              expect { produce }.to raise_error(exception, message)
              expect(sentry_events).to be_empty
            end
          end
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

  describe "#object_serialized" do
    subject(:method_call) do
      activity_log.new(object, activity_type).send(:object_serialized)
    end

    let(:object) { create(:credit_note, organization:) }
    let(:activity_type) { "object.created" }

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

      before do
        stub_const("Utils::ActivityLog::MAX_SERIALIZED_FEES", 2)
        create_list(:fee, 3, invoice: object)
      end

      it "returns the serialized invoice without fees" do
        expect(subject).to eq(serialized_object)
      end
    end

    context "when the object is a plan" do
      let_it_be(:object, refind: true) { create(:plan, organization:) }

      let(:serialized_object) do
        V1::PlanSerializer.new(
          object, root_name: :invoice, includes: Utils::ActivityLog::SERIALIZED_INCLUDED_OBJECTS[:plan] - [:charges]
        ).serialize
      end

      context "with many charges" do
        before do
          stub_const("Utils::ActivityLog::MAX_SERIALIZED_CHARGES", 2)
          create_list(:standard_charge, 3, plan: object)
        end

        it "returns the serialized plan without charges" do
          expect(subject).to eq(serialized_object)
        end
      end

      context "with many charge filters" do
        before do
          stub_const("Utils::ActivityLog::MAX_SERIALIZED_CHARGE_FILTERS", 2)
          charge = create(:standard_charge, plan: object)
          create_list(:charge_filter, 3, charge:)
        end

        it "returns the serialized plan without charges" do
          expect(subject).to eq(serialized_object)
        end
      end
    end

    context "when the object is a rate card" do
      let(:object) { create(:rate_card, organization:) }
      let(:tax) { create(:tax, organization:) }
      let(:active_rate) { create(:rate_card_rate, rate_card: object, organization:, effective_from: Time.current.beginning_of_day) }

      before do
        active_rate
        create(:rate_card_applied_tax, rate_card: object, tax:, organization:)
      end

      it "serializes the taxes" do
        expect(method_call[:taxes].pluck(:code)).to eq([tax.code])
      end

      context "when the rate card is deleted" do
        let(:activity_type) { "rate_card.deleted" }

        it "includes rates and assigned taxes without an active rate field" do
          expect(method_call).not_to have_key(:active_rate)
          expect(method_call[:rates].map { |rate| rate[:lago_id] }).to eq([active_rate.id])
          expect(method_call[:taxes].map { |item| item[:lago_id] }).to eq([tax.id])
        end
      end
    end

    context "when the object is a catalog plan" do
      let(:object) { create(:catalog_plan, organization:) }
      let(:tax) { create(:tax, organization:) }

      before { create(:plan_applied_tax, :catalog_plan, catalog_plan: object, tax:, organization:) }

      it "serializes the taxes" do
        expect(method_call[:taxes].pluck(:code)).to eq([tax.code])
      end
    end

    context "when the object is a subscription" do
      let(:object) { create(:subscription, organization:, plan:) }
      let(:serialized_object) do
        V1::SubscriptionSerializer.new(
          object, root_name: :invoice, includes: [{plan: Utils::ActivityLog::SERIALIZED_INCLUDED_OBJECTS[:plan] - [:charges]}]
        ).serialize
      end

      let_it_be(:plan, refind: true) { create(:plan, organization:) }

      context "with many charges" do
        before do
          stub_const("Utils::ActivityLog::MAX_SERIALIZED_CHARGES", 2)
          create_list(:standard_charge, 3, plan:)
        end

        it "returns the serialized subscription with plan excluding charges" do
          expect(subject).to eq(serialized_object)
        end
      end

      context "with many charge filters" do
        before do
          stub_const("Utils::ActivityLog::MAX_SERIALIZED_CHARGE_FILTERS", 2)
          charge = create(:standard_charge, plan:)
          create_list(:charge_filter, 3, charge:)
        end

        it "returns the serialized plan without charges" do
          expect(subject).to eq(serialized_object)
        end
      end
    end
  end

  describe "#serializer_includes" do
    subject(:method_call) do
      activity_log.new(object, serializer_activity_type).send(:serializer_includes, root_name)
    end

    let(:serializer_activity_type) { "object.created" }
    let(:root_name) { object.class.name.underscore.to_sym }

    context "when object is not an invoice" do
      let(:object) { create(:credit_note, organization:) }

      let(:serialized_includes) { Utils::ActivityLog::SERIALIZED_INCLUDED_OBJECTS[:credit_note] }

      it "returns the default includes for the object" do
        expect(method_call).to eq(serialized_includes)
      end
    end

    context "when object is a plan rate card" do
      let(:object) { create(:plan_rate_card, organization:) }

      context "when the activity updates the card" do
        let(:serializer_activity_type) { "plan_rate_card.updated" }

        it "includes the ordered phase sequence for the audit snapshot" do
          expect(method_call).to eq([:rate_phases])
        end
      end

      it "does not include phases for a non-update activity" do
        expect(method_call).to eq([])
      end
    end

    context "when object is a quote" do
      let(:object) { create(:quote, organization:) }

      it "includes the owners" do
        expect(method_call).to eq(%i[owners])
      end
    end

    context "when object is a quote version" do
      let(:object) { create(:quote_version, organization:) }

      it "includes the billing items but not the content" do
        expect(method_call).to eq(%i[billing_items])
      end
    end

    context "when object is a rate card" do
      let(:object) { create(:rate_card, organization:) }

      it "includes rates and taxes" do
        expect(method_call).to eq(%i[rates taxes])
      end
    end

    context "when object is an invoice" do
      let(:object) { create(:invoice, organization:) }

      context "when invoice has more fees than the limit" do
        let(:serializer_includes) { Utils::ActivityLog::SERIALIZED_INCLUDED_OBJECTS[:invoice] - [:fees] }

        before do
          stub_const("Utils::ActivityLog::MAX_SERIALIZED_FEES", 2)
          create_list(:fee, 3, invoice: object)
        end

        it "excludes fees from the includes" do
          expect(subject).to eq(serializer_includes)
        end
      end

      context "when invoice has fewer or equal fees than the limit" do
        let(:serializer_includes) { Utils::ActivityLog::SERIALIZED_INCLUDED_OBJECTS[:invoice] }

        before do
          stub_const("Utils::ActivityLog::MAX_SERIALIZED_FEES", 2)
          create_list(:fee, 2, invoice: object)
        end

        it "includes fees in the includes" do
          expect(subject).to eq(serializer_includes)
        end
      end
    end

    context "when object is a plan" do
      let_it_be(:object, refind: true) { create(:plan, organization:) }

      context "when plan has more charges than the limit" do
        let(:serializer_includes) { Utils::ActivityLog::SERIALIZED_INCLUDED_OBJECTS[:plan] - [:charges] }

        before do
          stub_const("Utils::ActivityLog::MAX_SERIALIZED_CHARGES", 2)
          create_list(:standard_charge, 3, plan: object)
        end

        it "excludes charges from the includes" do
          expect(subject).to eq(serializer_includes)
        end
      end

      context "when plan has fewer charges than the limit" do
        let(:serializer_includes) { Utils::ActivityLog::SERIALIZED_INCLUDED_OBJECTS[:plan] }

        before { create_list(:standard_charge, 2, plan: object) }

        it "includes charges in the includes" do
          expect(subject).to eq(serializer_includes)
        end
      end

      context "when plan has more charge filters than the limit" do
        let(:serializer_includes) { Utils::ActivityLog::SERIALIZED_INCLUDED_OBJECTS[:plan] - [:charges] }

        before do
          stub_const("Utils::ActivityLog::MAX_SERIALIZED_CHARGE_FILTERS", 2)
          charge = create(:standard_charge, plan: object)
          create_list(:charge_filter, 3, charge:)
        end

        it "excludes charges from the includes" do
          expect(subject).to eq(serializer_includes)
        end
      end

      context "when plan has fewer charge filters than the limit" do
        let(:serializer_includes) { Utils::ActivityLog::SERIALIZED_INCLUDED_OBJECTS[:plan] }

        before do
          charge = create(:standard_charge, plan: object)
          create_list(:charge_filter, 3, charge:)
        end

        it "excludes charges from the includes" do
          expect(subject).to eq(serializer_includes)
        end
      end
    end

    context "when object is a subscription" do
      let(:object) { create(:subscription, organization:, plan:) }

      let_it_be(:plan, refind: true) { create(:plan, organization:) }

      context "when subscription's plan has more charges than the limit" do
        let(:serializer_includes) { [{plan: Utils::ActivityLog::SERIALIZED_INCLUDED_OBJECTS[:plan] - [:charges]}] }

        before do
          stub_const("Utils::ActivityLog::MAX_SERIALIZED_CHARGES", 2)
          create_list(:standard_charge, 3, plan:)
        end

        it "excludes charges from the includes" do
          expect(subject).to eq(serializer_includes)
        end
      end

      context "when subscription's plan has fewer charges than the limit" do
        let(:serializer_includes) { Utils::ActivityLog::SERIALIZED_INCLUDED_OBJECTS[:subscription] }

        before { create_list(:standard_charge, 2, plan:) }

        it "includes charges in the includes" do
          expect(subject).to eq(serializer_includes)
        end
      end

      context "when subscription's plan has more charge filters than the limit" do
        let(:serializer_includes) { [{plan: Utils::ActivityLog::SERIALIZED_INCLUDED_OBJECTS[:plan] - [:charges]}] }

        before do
          stub_const("Utils::ActivityLog::MAX_SERIALIZED_CHARGE_FILTERS", 2)
          charge = create(:standard_charge, plan:)
          create_list(:charge_filter, 3, charge:)
        end

        it "excludes charges from the includes" do
          expect(subject).to eq(serializer_includes)
        end
      end

      context "when subscription's plan has fewer charge filters than the limit" do
        let(:serializer_includes) { Utils::ActivityLog::SERIALIZED_INCLUDED_OBJECTS[:subscription] }

        before do
          charge = create(:standard_charge, plan:)
          create_list(:charge_filter, 2, charge:)
        end

        it "includes charges in the includes" do
          expect(subject).to eq(serializer_includes)
        end
      end
    end
  end
end
