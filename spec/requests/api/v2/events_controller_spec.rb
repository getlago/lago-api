# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::EventsController, :capture_kafka_messages do
  let(:organization) { create_default(:organization, feature_flags: ["product_catalog"]) }
  let(:attributes) { valid_attributes }
  let(:valid_attributes) do
    {code: metric.code, transaction_id: "created-event", external_contract_id: contract.external_id,
     timestamp: Time.current.to_f, precise_total_amount_cents: "123.45", properties: {region: "eu"}}
  end
  let(:contract) { create(:contract, organization:, external_id: "contract.eu") }
  let(:metric) { create(:billable_metric, organization:, code: "api.requests") }
  let(:event) do
    create(:event, organization:, external_subscription_id: contract.external_id, code: metric.code,
      transaction_id: "transaction.eu", properties: {"region" => "eu"}, precise_total_amount_cents: "123.45")
  end

  def expected_payload(record)
    {
      lago_id: record.id,
      transaction_id: record.transaction_id,
      lago_customer_id: record.customer_id,
      external_contract_id: record.external_subscription_id,
      code: record.code,
      precise_total_amount_cents: record.precise_total_amount_cents&.to_s,
      properties: record.properties.deep_symbolize_keys,
      timestamp: record.timestamp.iso8601(6),
      created_at: record.created_at.iso8601(6),
      updated_at: record.updated_at.iso8601(6),
      deleted_at: record.deleted_at&.iso8601(6)
    }
  end

  shared_examples "rejects unsupported filters" do
    %i[external_subscription_id created_at_from created_at_to].each do |field|
      ["2026-10-01T00:00:00Z", nil, ["invalid"], {value: "invalid"}].each do |value|
        context "with unsupported filter #{field}: #{value.inspect}" do
          let(:params) { {:external_contract_id => "contract.eu", field => value} }

          it "rejects the filter even alongside a supported one" do
            request

            expect(response).to have_http_status(:unprocessable_content)
            expect(json).to eq(code: "validation_errors", details: [{code: "value_is_invalid", field: field.to_s, meta: {}}])
          end
        end
      end
    end

    context "with several unsupported filters" do
      let(:params) { {created_at_to: nil, created_at_from: nil, external_subscription_id: nil} }

      it "reports every unsupported filter" do
        request

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [
          {code: "value_is_invalid", field: "external_subscription_id", meta: {}},
          {code: "value_is_invalid", field: "created_at_from", meta: {}},
          {code: "value_is_invalid", field: "created_at_to", meta: {}}
        ])
      end
    end
  end

  describe "GET /api/v2/events" do
    subject(:request) { get_with_token(organization, path, params) }

    let(:path) { "/api/v2/events" }
    let(:params) { {} }

    before { event }

    include_examples "requires API permission", "event", "read"
    include_examples "rejects unsupported filters"

    it "returns flat events with cursor metadata" do
      request

      expect(response).to have_http_status(:ok)
      expect(json).to eq(events: [expected_payload(event)], meta: {next_cursor: nil, prev_cursor: nil})
    end

    it_behaves_like "a cursor paginated v2 endpoint", collection: :events, model: Event do
      let(:paginated_path) { path }
      let(:create_paginated_record) do
        ->(created_at) { create(:event, organization:, external_subscription_id: contract.external_id, created_at:) }
      end
    end

    context "when filtering by a contract" do
      let(:params) { {external_contract_id: contract.external_id} }
      let(:other_event) { create(:event, organization:, external_subscription_id: "other") }

      before { other_event }

      it "does not return another contract's events" do
        request

        expect(response).to have_http_status(:ok)
        expect(json[:events]).to eq([expected_payload(event)])
      end
    end

    context "when contracts reuse a transaction id" do
      let(:params) { {transaction_id: event.transaction_id} }
      let(:matching_event) do
        create(:event, organization:, external_subscription_id: "other-contract", transaction_id: event.transaction_id,
          created_at: event.created_at + 1.second)
      end
      let(:other_event) { create(:event, organization:, external_subscription_id: contract.external_id) }

      before do
        matching_event
        other_event
      end

      it "lists all matching events rather than choosing one" do
        request

        expect(response).to have_http_status(:ok)
        expect(json[:events]).to eq([expected_payload(matching_event), expected_payload(event)])
      end

      context "with a contract filter" do
        let(:params) { super().merge(external_contract_id: contract.external_id) }

        it "lists only the matching contract's event" do
          request

          expect(response).to have_http_status(:ok)
          expect(json[:events]).to eq([expected_payload(event)])
        end
      end
    end

    context "with malformed scalar filters" do
      %i[code transaction_id external_contract_id timestamp_from_started_at].each do |field|
        context "with an array for #{field}" do
          let(:params) { {field => ["invalid"]} }

          it "rejects the filter rather than returning an unfiltered list" do
            request

            expect(response).to have_http_status(:unprocessable_content)
            meta = (field == :timestamp_from_started_at) ? {allowed_values: %w[true false]} : {}
            expect(json).to eq(code: "validation_errors", details: [{code: "value_is_invalid", field: field.to_s, meta:}])
          end
        end
      end
    end

    context "with an invalid timestamp bound" do
      let(:params) { {timestamp_from: "not-a-date"} }

      it "identifies the invalid bound" do
        request

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [{code: "invalid_date", field: "timestamp_from", meta: {}}])
      end
    end

    context "with timestamp_from_started_at" do
      let(:params) { {external_contract_id: contract.external_id, timestamp_from_started_at: true} }
      let(:event) { create(:event, organization:, external_subscription_id: contract.external_id, timestamp: contract.started_at + 1.hour) }
      let(:earlier_event) { create(:event, organization:, external_subscription_id: contract.external_id, timestamp: contract.started_at - 1.hour) }

      before { earlier_event }

      it "uses the contract start, not a subscription" do
        request

        expect(response).to have_http_status(:ok)
        expect(json[:events]).to eq([expected_payload(event)])
      end
    end

    context "with another organization's event" do
      let(:foreign_event) { create(:event, organization: create(:organization)) }

      before { foreign_event }

      it "keeps the list organization-scoped" do
        request

        expect(json[:events]).to eq([expected_payload(event)])
      end
    end

    context "with a discarded event" do
      let(:event) { create(:event, organization:, external_subscription_id: contract.external_id, deleted_at: Time.current) }

      it "does not list the discarded event" do
        request

        expect(response).to have_http_status(:ok)
        expect(json[:events]).to eq([])
      end
    end

    context "with an expansion" do
      let(:params) { {expands: ["contract"]} }

      it "rejects undeclared relationships" do
        request

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("expand_not_supported")
      end
    end

    context "without product catalog", product_catalog: false do
      let(:organization) { create(:organization) }

      it "refuses the endpoint" do
        request

        expect(response).to have_http_status(:forbidden)
        expect(json).to eq(code: "feature_unavailable", details: [])
      end
    end
  end

  shared_examples "validates event input" do
    context "with nested properties" do
      let(:attributes) { super().merge(properties: {:values => [1, nil, {flag: true}], "bad\u0000key" => "value"}) }

      it "preserves null entries in properties and strips null bytes" do
        request

        expect(response).to have_http_status(:ok)
        payload = json[:event] || json[:events].first
        expect(payload[:properties]).to eq(values: [1, nil, {flag: true}], badkey: "value")
      end
    end

    context "with unpermitted ownership fields" do
      let(:attributes) { super().merge(organization_id: SecureRandom.uuid, customer_id: SecureRandom.uuid) }

      it "ignores them rather than changing ownership" do
        request

        expect(response).to have_http_status(:ok)
        expect(Event.find_by!(transaction_id: "created-event")).to have_attributes(organization_id: organization.id, customer_id: nil)
      end
    end

    [
      {external_subscription_id: "subscription"},
      {external_subscription_id: nil, external_contract_id: "contract.eu"},
      {external_subscription_id: "subscription", external_contract_id: "contract.eu"}
    ].each do |identifiers|
      context "with unsupported identifiers #{identifiers.inspect}" do
        let(:attributes) { super().except(:external_contract_id).merge(identifiers) }

        it "rejects the subscription field without storing or publishing any events" do
          expect { request }.not_to change(Event, :count)

          expect(response).to have_http_status(:unprocessable_content)
          expect(json).to eq(code: "validation_errors",
            details: [{code: "value_is_invalid", field: "#{error_prefix}external_subscription_id", meta: {}}])
          expect(Events::PostProcessJob).not_to have_been_enqueued
          expect(karafka_producer).not_to have_received(:produce_many_async)
        end
      end
    end

    context "with a 1,000-character transaction id" do
      let(:attributes) { super().merge(transaction_id: "a" * 1_000) }

      it "accepts the maximum length without truncating it" do
        request

        expect(response).to have_http_status(:ok)
        payload = json[:event] || json[:events].first
        expect(payload[:transaction_id]).to eq(attributes[:transaction_id])
      end
    end

    context "with a transaction id longer than 1,000 characters" do
      let(:attributes) { super().merge(transaction_id: "a" * 1_001) }

      it "rejects the request before storing or publishing any events" do
        expect { request }.not_to change(Event, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors",
          details: [{code: "value_is_too_long", field: "#{error_prefix}transaction_id", meta: {max_length: 1_000}}])
        expect(Events::PostProcessJob).not_to have_been_enqueued
        expect(karafka_producer).not_to have_received(:produce_many_async)
      end
    end

    {
      transaction_id: [123, [], {}], code: [123, [], {}], external_contract_id: [false, [], {}],
      properties: [123, "invalid", []], timestamp: [false, [], {}], precise_total_amount_cents: ["invalid", "NaN", [], {}]
    }.each do |field, values|
      values.each do |value|
        context "when #{field} is #{value.inspect}" do
          let(:attributes) { super().merge(field => value) }

          it "refuses the event without writing or scheduling it" do
            expect { request }.not_to change(Event, :count)

            expect(response).to have_http_status(:unprocessable_content)
            code = (field == :timestamp) ? "invalid_format" : "value_is_invalid"
            expect(json).to eq(code: "validation_errors", details: [{code:, field: "#{error_prefix}#{field}", meta: {}}])
            expect(Events::PostProcessJob).not_to have_been_enqueued
          end
        end
      end
    end
  end

  shared_examples "handles event expressions" do |error_field:|
    context "with a billable metric expression" do
      let(:metric) { create(:sum_billable_metric, organization:, field_name: "value", expression: "event.properties.a + event.properties.b") }
      let(:valid_attributes) { super().merge(properties: {a: "1", b: "2"}) }

      it "uses the existing expression evaluation" do
        request

        expect(response).to have_http_status(:ok)
        payload = json[:event] || json[:events].first
        expect(payload[:properties]).to eq(a: "1", b: "2", value: "3.0")
      end

      context "with incomplete expression properties" do
        let(:attributes) { super().merge(properties: {a: "1"}) }

        it "returns a token error without writing or scheduling events" do
          expect { request }.not_to change(Event, :count)

          expect(response).to have_http_status(:unprocessable_content)
          expect(json).to eq(code: "validation_errors", details: [{code: "expression_evaluation_failed", field: error_field, meta: {}}])
          expect(Events::PostProcessJob).not_to have_been_enqueued
        end
      end
    end
  end

  describe "POST /api/v2/events" do
    subject(:request) { post_with_token(organization, "/api/v2/events", event: attributes) }

    let(:error_prefix) { "" }

    include_examples "requires API permission", "event", "write"
    include_examples "validates event input"
    include_examples "handles event expressions", error_field: "base"

    it "creates an event through the existing ingestion service" do
      expect { request }.to change(Event, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(json).to eq(event: expected_payload(Event.find_by!(transaction_id: "created-event")))
      expect(Events::PostProcessJob).to have_been_enqueued.once
    end

    context "with a duplicate transaction" do
      let(:event) { create(:event, organization:, external_subscription_id: contract.external_id, transaction_id: attributes[:transaction_id]) }

      before { event }

      it "returns the exact duplicate error without another write" do
        expect { request }.not_to change(Event, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [{code: "value_already_exist", field: "transaction_id", meta: {}}])
      end
    end

    [nil, "invalid", []].each do |value|
      context "with wrapper #{value.inspect}" do
        let(:attributes) { value }

        it "returns a missing-parameter error" do
          expect { request }.not_to change(Event, :count)

          expect(response).to have_http_status(:bad_request)
          expect(json[:code]).to eq("missing_parameter")
        end
      end
    end
  end

  describe "POST /api/v2/events/batch" do
    subject(:request) { post_with_token(organization, "/api/v2/events/batch", events: batch) }

    let(:batch) { [attributes, valid_attributes.merge(transaction_id: "second-event")] }
    let(:error_prefix) { "events[0]." }

    include_examples "requires API permission", "event", "write"
    include_examples "validates event input"
    include_examples "handles event expressions", error_field: "events[0]"

    it "creates the whole batch and returns flat event payloads" do
      expect { request }.to change(Event, :count).by(2)

      expect(response).to have_http_status(:ok)
      expect(json).to eq(events: %w[created-event second-event].map { expected_payload(Event.find_by!(transaction_id: it)) })
      expect(Events::PostProcessJob).to have_been_enqueued.twice
    end

    [nil, "invalid", [], {}, [nil], ["invalid"], [["invalid"]]].each do |value|
      context "with malformed batch #{value.inspect}" do
        let(:batch) { value }

        it "does not silently discard invalid entries" do
          expect { request }.not_to change(Event, :count)

          expect(response).to have_http_status(:unprocessable_content)
          expect(json[:code]).to eq("validation_errors")
          expect(Events::PostProcessJob).not_to have_been_enqueued
        end
      end
    end

    [nil, "invalid", []].each do |value|
      context "with a valid event followed by #{value.inspect}" do
        let(:batch) { [attributes, value] }

        it "rejects the entire batch with the original array index" do
          expect { request }.not_to change(Event, :count)

          expect(response).to have_http_status(:unprocessable_content)
          expect(json).to eq(code: "validation_errors", details: [{code: "value_is_invalid", field: "events[1]", meta: {}}])
          expect(Events::PostProcessJob).not_to have_been_enqueued
        end
      end
    end

    context "with too many events" do
      let(:batch) { Array.new(Events::CreateBatchService::MAX_LENGTH + 1) { attributes } }

      it "rejects the batch before writing" do
        expect { request }.not_to change(Event, :count)

        expect(json).to eq(code: "validation_errors", details: [{code: "too_many_events", field: "events", meta: {}}])
      end
    end

    context "with an invalid timestamp on the second event" do
      let(:batch) { [attributes, attributes.merge(transaction_id: "second-event", timestamp: "invalid")] }

      it "reports the indexed service error and writes nothing" do
        expect { request }.not_to change(Event, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [{code: "invalid_format", field: "events[1].timestamp", meta: {}}])
      end
    end

    context "with a subscription id on the second event" do
      let(:batch) { [attributes, attributes.merge(transaction_id: "second-event", external_subscription_id: "subscription")] }

      it "rejects the whole batch without storing or publishing the first event" do
        expect { request }.not_to change(Event, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors",
          details: [{code: "value_is_invalid", field: "events[1].external_subscription_id", meta: {}}])
        expect(Events::PostProcessJob).not_to have_been_enqueued
        expect(karafka_producer).not_to have_received(:produce_many_async)
      end
    end

    context "with an oversized transaction id on the second event" do
      let(:batch) { [attributes, attributes.merge(transaction_id: "a" * 1_001)] }

      it "rejects the whole batch without storing or publishing the first event" do
        expect { request }.not_to change(Event, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors",
          details: [{code: "value_is_too_long", field: "events[1].transaction_id", meta: {max_length: 1_000}}])
        expect(Events::PostProcessJob).not_to have_been_enqueued
        expect(karafka_producer).not_to have_received(:produce_many_async)
      end
    end

    context "with duplicate transaction ids", transaction: false do
      let(:batch) { [attributes, attributes] }

      it "rolls back the whole batch and identifies the duplicate" do
        expect { request }.not_to change(Event, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [{code: "value_already_exist", field: "events[1].transaction_id", meta: {}}])
        expect(Events::PostProcessJob).not_to have_been_enqueued
      end
    end
  end

  describe "removed v2 routes", v2_timestamps: false do
    [
      [:get, "/events/example.eu"], [:get, "/events_enriched"], [:post, "/events/estimate_fees"], [:post, "/events/estimate_instant_fees"],
      [:post, "/events/batch_estimate_instant_fees"], [:put, "/events/example"], [:delete, "/events/example"]
    ].each do |verb, path|
      it "returns 404 for #{verb.upcase} #{path}" do
        public_send(:"#{verb}_with_token", organization, "/api/v2#{path}")

        expect(response).to be_not_found_error("resource")
        expect(response.headers["X-Lago-Endpoint-Status"]).to eq("beta")
      end
    end
  end

  describe "PostgreSQL ingestion without a product topic" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("LAGO_KAFKA_BOOTSTRAP_SERVERS").and_return("kafka")
      allow(ENV).to receive(:[]).with("LAGO_KAFKA_RAW_EVENTS_TOPIC").and_return("subscription-events")
      allow(ENV).to receive(:[]).with("LAGO_KAFKA_PRODUCT_RAW_EVENTS_TOPIC").and_return(nil)
    end

    it "stores a single event without publishing to the subscription topic" do
      expect { post_with_token(organization, "/api/v2/events", event: attributes) }.to change(Event, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(karafka_producer).not_to have_received(:produce_many_async)
    end

    it "stores a batch without publishing to the subscription topic" do
      expect {
        post_with_token(organization, "/api/v2/events/batch", events: [attributes, attributes.merge(transaction_id: "second-event")])
      }.to change(Event, :count).by(2)

      expect(response).to have_http_status(:ok)
      expect(karafka_producer).not_to have_received(:produce_many_async)
    end

    context "without Kafka" do
      before { allow(ENV).to receive(:[]).with("LAGO_KAFKA_BOOTSTRAP_SERVERS").and_return(nil) }

      it "keeps PostgreSQL-only ingestion available" do
        expect { post_with_token(organization, "/api/v2/events", event: attributes) }.to change(Event, :count).by(1)

        expect(response).to have_http_status(:ok)
        expect(Events::PostProcessJob).to have_been_enqueued.once
      end
    end
  end

  describe "ClickHouse events", clickhouse: true do
    let(:organization) { create_default(:organization, feature_flags: ["product_catalog"], clickhouse_events_store: true) }
    let(:enriched_at) { Time.zone.parse("2026-10-01T10:00:00.123Z") }
    let(:event_timestamp) { Time.zone.parse("2026-10-01T09:00:00.456Z") }
    let(:enriched_event) do
      create(:clickhouse_product_events_enriched, organization:, external_contract_id: "contract.eu", transaction_id: "transaction.eu",
        timestamp: event_timestamp, enriched_at:, precise_total_amount_cents: "123.45", attribution_labels: {"region" => "eu"})
    end

    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("LAGO_KAFKA_BOOTSTRAP_SERVERS").and_return("kafka")
      allow(ENV).to receive(:[]).with("LAGO_KAFKA_PRODUCT_RAW_EVENTS_TOPIC").and_return("product-events")
      enriched_event
    end

    def expected_enriched_payload(record)
      {
        transaction_id: record.transaction_id,
        external_contract_id: record.external_contract_id,
        code: record.code,
        precise_total_amount_cents: record.precise_total_amount_cents&.to_s,
        properties: record.properties.deep_symbolize_keys,
        timestamp: record.timestamp.iso8601(6),
        enriched_at: record.enriched_at.iso8601(6),
        value: record.value,
        decimal_value: record.decimal_value&.to_s,
        attribution_labels: record.attribution_labels.deep_symbolize_keys
      }
    end

    context "with unsupported list filters" do
      subject(:request) { get_with_token(organization, "/api/v2/events", params) }

      include_examples "rejects unsupported filters"
    end

    it "lists enriched product events" do
      get_with_token(organization, "/api/v2/events")

      expect(response).to have_http_status(:ok)
      expect(json).to eq(events: [expected_enriched_payload(enriched_event)], meta: {next_cursor: nil, prev_cursor: nil})
    end

    it "filters on event time rather than processing time" do
      get_with_token(organization, "/api/v2/events", timestamp_from: event_timestamp.iso8601(6), timestamp_to: event_timestamp.iso8601(6))

      expect(response).to have_http_status(:ok)
      expect(json[:events]).to eq([expected_enriched_payload(enriched_event)])
    end

    it "can count enriched events without PostgreSQL-only settings" do
      get_with_token(organization, "/api/v2/events", include_total_count: true)

      expect(response).to have_http_status(:ok)
      expect(json[:meta]).to eq(next_cursor: nil, prev_cursor: nil, total_count: 1)
    end

    context "when the count is capped" do
      let(:second_event) { create(:clickhouse_product_events_enriched, organization:, transaction_id: "second", enriched_at:) }

      before do
        second_event
        stub_const("CursorPagination::TotalCount::MAX_COUNTED_RECORDS", 1)
      end

      it "returns the capped lower bound as estimated" do
        get_with_token(organization, "/api/v2/events", include_total_count: true)

        expect(response).to have_http_status(:ok)
        expect(json[:meta]).to eq(next_cursor: nil, prev_cursor: nil, total_count: 2, total_count_estimated: true)
      end
    end

    context "when multiple contracts reuse a transaction id and event time" do
      let(:enriched_events) do
        %w[contract.a contract.b contract.c contract.d].map do |external_contract_id|
          create(:clickhouse_product_events_enriched, organization:, external_contract_id:, transaction_id: "same-transaction",
            timestamp: event_timestamp, enriched_at:)
        end
      end
      let(:reprocessed_event) do
        create(:clickhouse_product_events_enriched, organization:, external_contract_id: "contract.a", transaction_id: "same-transaction",
          timestamp: event_timestamp, enriched_at: enriched_at + 1.day, value: "42.0")
      end

      before { enriched_events }

      def fetch_event_page(params = {})
        get_with_token(organization, "/api/v2/events", params)
        expect(response).to have_http_status(:ok)
        json
      end

      it "visits every event once in both directions" do
        all_events = fetch_event_page[:events]
        page = fetch_event_page(limit: 2)
        forward = []
        loop do
          forward.concat(page[:events])
          break unless page[:meta][:next_cursor]

          page = fetch_event_page(limit: 2, after: page[:meta][:next_cursor])
        end

        backward = []
        loop do
          backward.unshift(*page[:events])
          break unless page[:meta][:prev_cursor]

          page = fetch_event_page(limit: 2, before: page[:meta][:prev_cursor])
        end

        expect(forward).to eq(all_events)
        expect(backward).to eq(all_events)
        expect(all_events.size).to eq(5)
      end

      it "lists the matching event when filtering by transaction and contract" do
        get_with_token(organization, "/api/v2/events", transaction_id: "same-transaction", external_contract_id: "contract.b")

        expect(response).to have_http_status(:ok)
        expect(json[:events]).to eq([expected_enriched_payload(enriched_events.second)])
      end

      it "lists all contracts matching a transaction id" do
        get_with_token(organization, "/api/v2/events", transaction_id: "same-transaction")

        expect(response).to have_http_status(:ok)
        expect(json[:events]).to eq(enriched_events.reverse.map { expected_enriched_payload(it) })
      end

      it "does not skip an unseen event when it is reprocessed between pages" do
        page = fetch_event_page(limit: 2)
        seen_contracts = page[:events].map { it[:external_contract_id] }
        reprocessed_event

        while page[:meta][:next_cursor]
          page = fetch_event_page(limit: 2, after: page[:meta][:next_cursor])
          seen_contracts.concat(page[:events].map { it[:external_contract_id] })
        end

        expect(seen_contracts).to eq(%w[contract.eu contract.d contract.c contract.b contract.a])
      end
    end

    context "when enrichment has not completed" do
      let(:pending_event) do
        create(:clickhouse_product_events_raw, organization:, external_contract_id: "contract.eu", transaction_id: "pending-event")
      end

      before { pending_event }

      it "does not list the raw event" do
        get_with_token(organization, "/api/v2/events")

        expect(response).to have_http_status(:ok)
        expect(json[:events]).to eq([expected_enriched_payload(enriched_event)])
      end
    end

    context "when an event has multiple enrichment versions" do
      let(:new_version) do
        create(:clickhouse_product_events_enriched, organization:, external_contract_id: enriched_event.external_contract_id,
          code: enriched_event.code, transaction_id: enriched_event.transaction_id, timestamp: event_timestamp,
          enriched_at: enriched_at + 1.minute, value: "42.0", precise_total_amount_cents: "123.45")
      end

      before do
        Clickhouse::BaseRecord.connection.execute("SYSTEM STOP MERGES product_events_enriched")
        new_version
      end

      after { Clickhouse::BaseRecord.connection.execute("SYSTEM START MERGES product_events_enriched") }

      it "returns and counts only the latest version before background merges" do
        get_with_token(organization, "/api/v2/events", limit: 1, include_total_count: true)

        expect(response).to have_http_status(:ok)
        expect(json).to eq(events: [expected_enriched_payload(new_version)], meta: {next_cursor: nil, prev_cursor: nil, total_count: 1})
      end
    end

    context "when the catalog Kafka topic is not configured" do
      let(:legacy_event) do
        create(:clickhouse_events_raw, organization:, external_subscription_id: "contract.eu", transaction_id: "legacy-event",
          timestamp: event_timestamp, ingested_at: enriched_at)
      end

      before do
        allow(ENV).to receive(:[]).with("LAGO_KAFKA_PRODUCT_RAW_EVENTS_TOPIC").and_return(nil)
        legacy_event
      end

      it "still reads enriched product events, not the legacy fallback" do
        get_with_token(organization, "/api/v2/events")

        expect(response).to have_http_status(:ok)
        expect(json[:events]).to eq([expected_enriched_payload(enriched_event)])
      end

      %w[/events /events/batch].each do |path|
        it "refuses #{path} ingestion rather than publishing to the subscription topic" do
          expect { post_with_token(organization, "/api/v2#{path}", event: attributes, events: [attributes]) }.not_to change(Event, :count)

          expect(response).to have_http_status(:forbidden)
          expect(json).to eq(code: "endpoint_not_available", details: [])
          expect(karafka_producer).not_to have_received(:produce_many_async)
        end
      end
    end

    context "when creating an event" do
      let(:acknowledged_event) do
        {
          transaction_id: attributes[:transaction_id],
          external_contract_id: attributes[:external_contract_id],
          code: attributes[:code],
          timestamp: Time.current.iso8601(6),
          precise_total_amount_cents: attributes[:precise_total_amount_cents],
          properties: attributes[:properties]
        }
      end

      before { freeze_time }

      it "uses asynchronous ingestion without writing a PostgreSQL event" do
        expect { post_with_token(organization, "/api/v2/events", event: attributes) }.not_to change(Event, :count)

        expect(response).to have_http_status(:ok)
        expect(json).to eq(event: acknowledged_event)
        expect(Events::PostProcessJob).not_to have_been_enqueued
        expect(kafka_messages.map { it[:topic] }).to eq(["product-events"])
      end

      it "acknowledges receipt before the event appears in the list" do
        post_with_token(organization, "/api/v2/events", event: attributes)
        expect(response).to have_http_status(:ok)

        get_with_token(organization, "/api/v2/events", transaction_id: "created-event")

        expect(response).to have_http_status(:ok)
        expect(json[:events]).to eq([])
      end

      it "publishes a batch only to the product topic" do
        post_with_token(organization, "/api/v2/events/batch", events: [attributes, attributes.merge(transaction_id: "second-event")])

        expect(response).to have_http_status(:ok)
        expect(json).to eq(events: [acknowledged_event, acknowledged_event.merge(transaction_id: "second-event")])
        expect(kafka_messages.map { it[:topic] }).to eq(%w[product-events product-events])
      end

      context "with a subscription id" do
        let(:attributes) { super().merge(external_subscription_id: "subscription") }

        %w[/events /events/batch].each do |path|
          it "rejects #{path} before publishing to Kafka" do
            post_with_token(organization, "/api/v2#{path}", event: attributes, events: [attributes])

            expect(response).to have_http_status(:unprocessable_content)
            field = (path == "/events") ? "external_subscription_id" : "events[0].external_subscription_id"
            expect(json).to eq(code: "validation_errors", details: [{code: "value_is_invalid", field:, meta: {}}])
            expect(karafka_producer).not_to have_received(:produce_many_async)
          end
        end
      end

      context "without required fields" do
        let(:attributes) { super().except(:code, :transaction_id) }

        it "validates before sending an unsaved event to Kafka" do
          post_with_token(organization, "/api/v2/events", event: attributes)

          expect(response).to have_http_status(:unprocessable_content)
          expect(json).to eq(code: "validation_errors", details: %w[transaction_id code].map { {code: "value_is_mandatory", field: it, meta: {}} })
        end
      end

      context "with an oversized transaction id" do
        let(:attributes) { super().merge(transaction_id: "a" * 1_001) }

        %w[/events /events/batch].each do |path|
          it "rejects #{path} before publishing to Kafka" do
            post_with_token(organization, "/api/v2#{path}", event: attributes, events: [attributes])

            expect(response).to have_http_status(:unprocessable_content)
            field = (path == "/events") ? "transaction_id" : "events[0].transaction_id"
            expect(json).to eq(code: "validation_errors",
              details: [{code: "value_is_too_long", field:, meta: {max_length: 1_000}}])
            expect(karafka_producer).not_to have_received(:produce_many_async)
          end
        end
      end
    end

    context "when Kafka is not configured" do
      before { allow(ENV).to receive(:[]).with("LAGO_KAFKA_BOOTSTRAP_SERVERS").and_return(nil) }

      it "does not acknowledge an event it cannot ingest" do
        post_with_token(organization, "/api/v2/events", event: attributes)

        expect(response).to have_http_status(:forbidden)
        expect(json).to eq(code: "endpoint_not_available", details: [])
        expect(karafka_producer).not_to have_received(:produce_many_async)
      end
    end
  end
end
