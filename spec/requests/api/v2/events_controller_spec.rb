# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::EventsController do
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

  describe "GET /api/v2/events" do
    subject(:request) { get_with_token(organization, path, params) }

    let(:path) { "/api/v2/events" }
    let(:params) { {} }

    before { event }

    include_examples "requires API permission", "event", "read"

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

    it_behaves_like "a v2 list filtered on created_at", collection: :events do
      let(:filtered_path) { path }
      let(:create_filtered_record) do
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

    context "with malformed scalar filters" do
      %i[code external_contract_id external_subscription_id timestamp_from_started_at].each do |field|
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

    context "without product catalog", product_catalog: false do
      let(:organization) { create(:organization) }

      it "refuses the endpoint" do
        request

        expect(response).to have_http_status(:forbidden)
        expect(json).to eq(code: "feature_unavailable", details: [])
      end
    end
  end

  describe "GET /api/v2/events/:id" do
    subject(:request) { get_with_token(organization, "/api/v2/events/#{transaction_id}", params) }

    let(:transaction_id) { event.transaction_id }
    let(:params) { {} }

    include_examples "requires API permission", "event", "read"

    it "looks up a dotted transaction id and returns the complete payload" do
      request

      expect(response).to have_http_status(:ok)
      expect(json).to eq(event: expected_payload(event))
    end

    context "with a missing event" do
      let(:transaction_id) { "missing" }

      it "returns the v2 not-found error" do
        request

        expect(response).to be_v2_not_found_error("event")
      end
    end

    context "when another contract reused the transaction id" do
      let(:newer_event) do
        create(:event, organization:, external_subscription_id: "other-contract", transaction_id: event.transaction_id,
          created_at: event.created_at + 1.second)
      end

      before { newer_event }

      it "returns the latest event deterministically" do
        request

        expect(response).to have_http_status(:ok)
        expect(json).to eq(event: expected_payload(newer_event))
      end

      context "with a contract filter" do
        let(:params) { {external_contract_id: contract.external_id} }

        it "returns the event for that contract" do
          request

          expect(response).to have_http_status(:ok)
          expect(json).to eq(event: expected_payload(event))
        end
      end
    end

    context "with a discarded event" do
      let(:event) { create(:event, organization:, external_subscription_id: contract.external_id, deleted_at: Time.current) }

      it "does not expose the discarded event" do
        request

        expect(response).to be_v2_not_found_error("event")
      end
    end

    context "with another organization's event" do
      let(:event) { create(:event, organization: create(:organization)) }

      it "does not expose it" do
        request

        expect(response).to be_v2_not_found_error("event")
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
  end

  shared_examples "validates event input" do
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

    context "with nested properties" do
      let(:attributes) { super().merge(properties: {:values => [1, nil, {flag: true}], "bad\u0000key" => "value"}) }

      it "preserves null entries in properties and strips null bytes" do
        request

        expect(response).to have_http_status(:ok)
        expect(json[:event][:properties]).to eq(values: [1, nil, {flag: true}], badkey: "value")
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
      [:get, "/events_enriched"], [:post, "/events/estimate_fees"], [:post, "/events/estimate_instant_fees"],
      [:post, "/events/batch_estimate_instant_fees"], [:put, "/events/example"], [:delete, "/events/example"]
    ].each do |verb, path|
      it "returns 404 for #{verb.upcase} #{path}" do
        public_send(:"#{verb}_with_token", organization, "/api/v2#{path}")

        expect(response).to be_not_found_error("resource")
        expect(response.headers["X-Lago-Endpoint-Status"]).to eq("beta")
      end
    end
  end

  describe "ClickHouse events", clickhouse: true do
    let(:organization) { create_default(:organization, feature_flags: ["product_catalog"], clickhouse_events_store: true) }
    let(:ingested_at) { Time.zone.parse("2026-10-01T10:00:00.123Z") }
    let(:event_timestamp) { Time.zone.parse("2026-10-01T09:00:00.456Z") }
    let(:raw_event) do
      create(:clickhouse_product_events_raw, organization:, external_contract_id: "contract.eu", transaction_id: "transaction.eu",
        timestamp: event_timestamp, ingested_at:, precise_total_amount_cents: "123.45")
    end

    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("LAGO_KAFKA_PRODUCT_RAW_EVENTS_TOPIC").and_return("product-events")
      raw_event
    end

    def expected_raw_payload(record)
      {
        lago_id: nil,
        transaction_id: record.transaction_id,
        lago_customer_id: nil,
        external_contract_id: record.external_contract_id,
        code: record.code,
        precise_total_amount_cents: record.precise_total_amount_cents&.to_s,
        properties: record.properties.deep_symbolize_keys,
        timestamp: record.timestamp.iso8601(6),
        created_at: record.ingested_at.iso8601(6),
        updated_at: nil,
        deleted_at: nil
      }
    end

    it "lists product events rather than reading the legacy raw table" do
      get_with_token(organization, "/api/v2/events")

      expect(response).to have_http_status(:ok)
      expect(json).to eq(events: [expected_raw_payload(raw_event)], meta: {next_cursor: nil, prev_cursor: nil})
    end

    it "fetches a product event by its transaction id" do
      get_with_token(organization, "/api/v2/events/transaction.eu")

      expect(response).to have_http_status(:ok)
      expect(json).to eq(event: expected_raw_payload(raw_event))
    end

    it "uses ingestion time for the created_at date filter" do
      get_with_token(organization, "/api/v2/events", created_at_from: ingested_at.iso8601(6), created_at_to: ingested_at.iso8601(6))

      expect(response).to have_http_status(:ok)
      expect(json[:events]).to eq([expected_raw_payload(raw_event)])
    end

    it "can count raw events without PostgreSQL-only settings" do
      get_with_token(organization, "/api/v2/events", include_total_count: true)

      expect(response).to have_http_status(:ok)
      expect(json[:meta]).to eq(next_cursor: nil, prev_cursor: nil, total_count: 1)
    end

    context "when the count is capped" do
      let(:second_event) { create(:clickhouse_product_events_raw, organization:, transaction_id: "second", ingested_at:) }

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

    context "when multiple contracts reuse a transaction id and ingestion time" do
      let(:raw_events) do
        %w[contract.a contract.b contract.c contract.d].map do |external_contract_id|
          create(:clickhouse_product_events_raw, organization:, external_contract_id:, transaction_id: "same-transaction",
            timestamp: event_timestamp, ingested_at:)
        end
      end

      before { raw_events }

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

      it "can disambiguate a transaction by its contract id" do
        get_with_token(organization, "/api/v2/events/same-transaction", external_contract_id: "contract.b")

        expect(response).to have_http_status(:ok)
        expect(json).to eq(event: expected_raw_payload(raw_events.second))
      end
    end

    context "when the catalog Kafka topic is not configured" do
      let(:legacy_event) do
        create(:clickhouse_events_raw, organization:, external_subscription_id: "contract.eu", transaction_id: "legacy-event",
          timestamp: event_timestamp, ingested_at:)
      end

      before do
        allow(ENV).to receive(:[]).with("LAGO_KAFKA_PRODUCT_RAW_EVENTS_TOPIC").and_return(nil)
        legacy_event
      end

      it "reads the same legacy fallback as the producer" do
        get_with_token(organization, "/api/v2/events")

        expect(response).to have_http_status(:ok)
        expect(json[:events].map { it[:transaction_id] }).to eq(["legacy-event"])
        expect(json[:events].first[:external_contract_id]).to eq("contract.eu")
      end
    end

    context "when creating an event" do
      it "uses asynchronous ingestion without writing a PostgreSQL event" do
        expect { post_with_token(organization, "/api/v2/events", event: attributes) }.not_to change(Event, :count)

        expect(response).to have_http_status(:ok)
        expect(json[:event][:external_contract_id]).to eq(contract.external_id)
        expect(Events::PostProcessJob).not_to have_been_enqueued
      end

      context "without required fields" do
        let(:attributes) { super().except(:code, :transaction_id) }

        it "validates before sending an unsaved event to Kafka" do
          post_with_token(organization, "/api/v2/events", event: attributes)

          expect(response).to have_http_status(:unprocessable_content)
          expect(json).to eq(code: "validation_errors", details: %w[transaction_id code].map { {code: "value_is_mandatory", field: it, meta: {}} })
        end
      end
    end
  end
end
