# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::BillableMetricsController do
  let_it_be(:organization, refind: true) { create_default(:organization, feature_flags: ["product_catalog"]) }

  let(:metric) { create(:billable_metric, organization:, code: "api.requests") }
  let(:expected_payload) do
    {
      lago_id: metric.id,
      name: metric.name,
      code: metric.code,
      description: metric.description,
      aggregation_type: metric.aggregation_type,
      weighted_interval: metric.weighted_interval,
      recurring: metric.recurring,
      rounding_function: metric.rounding_function,
      rounding_precision: metric.rounding_precision,
      field_name: metric.field_name,
      expression: metric.expression,
      created_at: metric.created_at.iso8601(6),
      updated_at: metric.updated_at.iso8601(6),
      deleted_at: metric.deleted_at&.iso8601(6)
    }
  end

  shared_examples "validates billable metric input" do
    {
      aggregation_type: ["unknown", 123, nil],
      weighted_interval: ["minutes", 123],
      rounding_function: ["unknown", 123],
      recurring: ["unknown", nil],
      expression: [123],
      rounding_precision: ["unknown", 1.5, "0x10", "2_000"]
    }.each do |field, values|
      values.each do |value|
        context "with #{field} set to #{value.inspect}" do
          let(:attributes) { super().merge(field => value) }

          it "returns a validation error without writing a metric" do
            expect { request }.not_to change { organization.billable_metrics.pluck(:id, :name, :updated_at) }

            expect(response).to have_http_status(:unprocessable_content)
            expect(json).to eq(code: "validation_errors", details: [{code: "value_is_invalid", field: field.to_s, meta: {}}])
          end
        end
      end
    end
  end

  shared_examples "reports indexed filter errors" do
    context "when the second filter has empty values" do
      let(:attributes) { super().merge(filters: [{key: "region", values: ["eu"]}, {key: "cloud", values: []}]) }

      it "identifies the invalid filter without writing a metric" do
        expect { request }.not_to change { organization.billable_metrics.pluck(:id, :name, :updated_at) }

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:details]).to eq([{code: "value_is_mandatory", field: "filters[1].values", meta: {}}])
      end
    end

    context "when the second filter has no key" do
      let(:attributes) { super().merge(filters: [{key: "region", values: ["eu"]}, {values: ["aws"]}]) }

      it "identifies the missing key without writing a metric" do
        expect { request }.not_to change { organization.billable_metrics.pluck(:id, :name, :updated_at) }

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:details]).to eq([{code: "value_is_mandatory", field: "filters[1].key", meta: {}}])
      end
    end

    context "when a filter key is repeated" do
      let(:attributes) { super().merge(filters: [{key: "region", values: ["eu"]}, {key: "region", values: ["us"]}]) }

      it "identifies the repeated key without writing a metric" do
        expect { request }.not_to change { organization.billable_metrics.pluck(:id, :name, :updated_at) }

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:details]).to eq([{code: "value_already_exist", field: "filters[1].key", meta: {}}])
      end
    end
  end

  shared_examples "rejects malformed filter input" do
    {
      "a scalar filters value" => ["invalid", "filters"],
      "an object instead of a filters array" => [{key: "region", values: ["eu"]}, "filters"],
      "a null filters value" => [nil, "filters"],
      "a scalar filter" => [["invalid"], "filters[0]"],
      "a null filter" => [[nil], "filters[0]"],
      "mixed valid and invalid filters" => [[{key: "region", values: ["eu"]}, "invalid"], "filters[1]"],
      "mixed valid and null filters" => [[{key: "region", values: ["eu"]}, nil], "filters[1]"],
      "an object filter key" => [[{key: {name: "region"}, values: ["eu"]}], "filters[0].key"],
      "a scalar values field" => [[{key: "region", values: "eu"}], "filters[0].values"],
      "an object values field" => [[{key: "region", values: {name: "eu"}}], "filters[0].values"],
      "a numeric filter value" => [[{key: "region", values: ["eu", 123]}], "filters[0].values[1]"],
      "a boolean filter value" => [[{key: "region", values: ["eu", false]}], "filters[0].values[1]"],
      "a null filter value" => [[{key: "region", values: ["eu", nil]}], "filters[0].values[1]"],
      "an object filter value" => [[{key: "region", values: ["eu", {name: "us"}]}], "filters[0].values[1]"]
    }.each do |description, (filters, field)|
      context "with #{description}" do
        let(:attributes) { super().merge(filters:) }

        it "rejects malformed filter input without changing metrics or filters" do
          expect { request }.not_to change {
            [
              organization.billable_metrics.with_discarded.order(:id).map(&:attributes),
              BillableMetricFilter.with_discarded.where(organization:).order(:id).map(&:attributes)
            ]
          }

          expect(response).to have_http_status(:unprocessable_content)
          expect(json).to eq(code: "validation_errors", details: [{code: "value_is_invalid", field:, meta: {}}])
        end
      end
    end
  end

  describe "GET /api/v2/billable_metrics" do
    subject(:request) { get_with_token(organization, "/api/v2/billable_metrics", params) }

    let(:params) { {} }

    before do
      metric
      create(:billable_metric_filter, billable_metric: metric)
      create(:billable_metric, :discarded, organization:)
      create(:billable_metric, organization: create(:organization))
    end

    include_examples "requires API permission", "billable_metric", "read"

    it "returns only kept metrics of the organization with flat payloads" do
      request

      expect(response).to have_http_status(:ok)
      expect(json).to eq(billable_metrics: [expected_payload], meta: {next_cursor: nil, prev_cursor: nil})
    end

    it_behaves_like "a cursor paginated v2 endpoint", collection: :billable_metrics, model: BillableMetric do
      let(:paginated_path) { "/api/v2/billable_metrics" }
      let(:create_paginated_record) { ->(created_at) { create(:billable_metric, organization:, created_at:) } }
    end

    it_behaves_like "a v2 list filtered on created_at", collection: :billable_metrics do
      let(:filtered_path) { "/api/v2/billable_metrics" }
      let(:create_filtered_record) { ->(created_at) { create(:billable_metric, organization:, created_at:) } }
    end
  end

  describe "GET /api/v2/billable_metrics/:code" do
    subject(:request) { get_with_token(organization, "/api/v2/billable_metrics/#{metric.code}", params) }

    let(:params) { {} }

    include_examples "requires API permission", "billable_metric", "read"

    it "returns the flat metric and preserves dots in its code" do
      request

      expect(response).to have_http_status(:ok)
      expect(json).to eq(billable_metric: expected_payload)
      expect(response.headers["X-Lago-Endpoint-Status"]).to eq("beta")
    end

    context "with the filters expansion" do
      let(:params) { {expands: ["filters"]} }
      let(:filter) { create(:billable_metric_filter, billable_metric: metric, key: "region", values: %w[us eu]) }

      before do
        filter
        create(:billable_metric_filter, billable_metric: metric, deleted_at: Time.current)
      end

      it "embeds only kept filters with v2 timestamps" do
        request

        expect(response).to have_http_status(:ok)
        expect(json).to eq(billable_metric: expected_payload.merge(filters: [{
          lago_id: filter.id,
          key: "region",
          values: %w[eu us],
          created_at: filter.created_at.iso8601(6),
          updated_at: filter.updated_at.iso8601(6),
          deleted_at: nil
        }]))
      end
    end

    context "with an unknown expansion" do
      let(:params) { {expands: ["plans"]} }

      it "returns an invalid expansion error" do
        request

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("invalid_expand")
      end
    end

    context "when the metric does not exist" do
      let(:metric) { build_stubbed(:billable_metric) }

      it "returns not found" do
        request

        expect(response).to be_v2_not_found_error("billable_metric")
      end
    end

    context "when the metric belongs to another organization" do
      let(:metric) { create(:billable_metric, organization: create(:organization)) }

      it "does not expose the foreign metric" do
        request

        expect(response).to be_v2_not_found_error("billable_metric")
      end
    end

    context "when the metric is discarded" do
      let(:metric) { create(:billable_metric, :discarded, organization:) }

      it "returns not found" do
        request

        expect(response).to be_v2_not_found_error("billable_metric")
      end
    end
  end

  describe "POST /api/v2/billable_metrics" do
    subject(:request) { post_with_token(organization, "/api/v2/billable_metrics", billable_metric: attributes) }

    let(:attributes) do
      {name: "API requests", code: "api.requests", aggregation_type: "sum_agg", field_name: "units",
       rounding_function: "ceil", rounding_precision: 2, filters: [{key: "region", values: %w[us eu]}]}
    end
    let(:metric) { organization.billable_metrics.find_by!(code: attributes[:code]) }

    include_examples "requires API permission", "billable_metric", "write"
    include_examples "validates billable metric input"
    include_examples "reports indexed filter errors"
    include_examples "rejects malformed filter input"

    it "creates the metric and its filters but returns a flat payload" do
      expect { request }.to change(organization.billable_metrics, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(json).to eq(billable_metric: expected_payload)
      expect(metric.filters.sole).to have_attributes(key: "region", values: %w[us eu])
      expect(SendWebhookJob).to have_been_enqueued.with("billable_metric.created", metric)
    end

    context "with null bytes in the filter key and values" do
      let(:attributes) { super().merge(filters: [{key: "reg\u0000ion", values: ["e\u0000u"]}]) }

      it "keeps the shared null-byte sanitization" do
        request

        expect(response).to have_http_status(:ok)
        expect(metric.filters.sole).to have_attributes(key: "region", values: ["eu"])
      end
    end

    context "with a decimal integer string for rounding precision" do
      let(:attributes) { super().merge(rounding_precision: "010") }

      it "stores its decimal value" do
        request

        expect(response).to have_http_status(:ok)
        expect(metric.rounding_precision).to eq(10)
        expect(json[:billable_metric][:rounding_precision]).to eq(10)
      end
    end

    context "when the code already exists" do
      before { create(:billable_metric, organization:, code: attributes[:code]) }

      it "does not update the existing metric" do
        expect { request }.not_to change { metric.reload.attributes }

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:details]).to eq([{code: "value_already_exist", field: "code", meta: {}}])
      end
    end

    context "when filters are invalid" do
      let(:attributes) { super().merge(filters: [{key: "region", values: []}]) }

      it "does not create a metric" do
        expect { request }.not_to change(BillableMetric, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:details]).to eq([{code: "value_is_mandatory", field: "filters[0].values", meta: {}}])
      end
    end

    [nil, "invalid", []].each do |body|
      context "with a malformed wrapper #{body.inspect}" do
        let(:attributes) { body }

        it "returns the v2 missing parameter error" do
          expect { request }.not_to change(BillableMetric, :count)

          expect(response).to have_http_status(:bad_request)
          expect(json).to eq(code: "missing_parameter", details: [{code: "missing", field: "billable_metric", meta: {}}])
        end
      end
    end
  end

  %i[put patch].each do |method|
    describe "#{method.upcase} /api/v2/billable_metrics/:code" do
      subject(:request) { public_send(:"#{method}_with_token", organization, "/api/v2/billable_metrics/#{metric.code}", billable_metric: attributes) }

      let(:attributes) { {name: "Updated requests"} }

      before { metric }

      include_examples "requires API permission", "billable_metric", "write"
      include_examples "validates billable metric input"
      include_examples "reports indexed filter errors"

      it "updates supplied fields and leaves other fields unchanged" do
        request

        expect(response).to have_http_status(:ok)
        expect(metric.reload).to have_attributes(name: "Updated requests", code: "api.requests", aggregation_type: "count_agg")
        expect(json).to eq(billable_metric: expected_payload)
        expect(SendWebhookJob).to have_been_enqueued.with("billable_metric.updated", metric)
      end

      context "with existing filters" do
        before do
          create(:billable_metric_filter, organization:, billable_metric: metric, key: "region", values: %w[us eu])
          create(:billable_metric_filter, organization:, billable_metric: metric, key: "cloud", values: %w[aws azure])
        end

        include_examples "rejects malformed filter input"

        it "leaves filters unchanged when they are omitted" do
          expect { request }.not_to change { metric.filters.order(:id).map(&:attributes) }

          expect(response).to have_http_status(:ok)
          expect(metric.reload.name).to eq("Updated requests")
        end

        context "when filters is explicitly empty" do
          let(:attributes) { super().merge(filters: []) }

          it "discards the existing filters" do
            expect { request }.to change { metric.filters.count }.from(2).to(0)

            expect(response).to have_http_status(:ok)
            expect(metric.filters.with_discarded.count).to eq(2)
            expect(metric.filters.with_discarded.all?(&:discarded?)).to be(true)
          end
        end
      end

      context "with a signed integer string for rounding precision" do
        let(:attributes) { super().merge(rounding_precision: "-2") }

        it "stores the integer without changing its sign" do
          request

          expect(response).to have_http_status(:ok)
          expect(metric.reload.rounding_precision).to eq(-2)
          expect(json[:billable_metric][:rounding_precision]).to eq(-2)
        end
      end

      context "when the metric is attached to a v1 plan" do
        let(:attributes) { super().merge(code: "changed", aggregation_type: "sum_agg", field_name: "units") }

        before { create(:standard_charge, organization:, billable_metric: metric) }

        it "refuses the locked fields without updating the metric" do
          expect { request }.not_to change { metric.reload.attributes }

          expect(response).to have_http_status(:unprocessable_content)
          expect(json[:details]).to eq(%w[code aggregation_type field_name].map { {code: "attached_to_plan", field: it, meta: {}} })
        end

        context "when the locked fields are sent back unchanged" do
          let(:attributes) { {name: "Updated requests", code: "api.requests", aggregation_type: "count_agg", field_name: nil} }

          it "updates the editable fields" do
            request

            expect(response).to have_http_status(:ok)
            expect(metric.reload).to have_attributes(name: "Updated requests", code: "api.requests")
          end
        end
      end

      context "when the metric belongs to another organization" do
        let(:metric) { create(:billable_metric, organization: create(:organization)) }

        it "does not update the foreign metric" do
          expect { request }.not_to change { metric.reload.attributes }

          expect(response).to be_v2_not_found_error("billable_metric")
        end
      end

      context "when the metric does not exist" do
        let(:metric) { build_stubbed(:billable_metric) }

        it "does not create a metric" do
          expect { request }.not_to change(BillableMetric, :count)

          expect(response).to be_v2_not_found_error("billable_metric")
        end
      end

      context "when a filter is referenced by a Product" do
        let(:filter) { create(:billable_metric_filter, billable_metric: metric, key: "region", values: %w[us eu]) }
        let(:product) { create(:product, organization:, billable_metric: metric) }
        let(:product_filter) { create(:product_filter, organization:, product:) }
        let(:attributes) { super().merge(filters: []) }

        before { create(:product_filter_value, organization:, product_filter:, billable_metric_filter: filter, value: "eu") }

        it "does not remove the filter or partially update the metric" do
          expect { request }.not_to change { metric.reload.attributes }

          expect(response).to have_http_status(:unprocessable_content)
          expect(filter.reload).not_to be_discarded
          expect(json[:details]).to eq([{code: "referenced_by_product_filter", field: "filters", meta: {}}])
        end
      end
    end
  end

  describe "DELETE /api/v2/billable_metrics/:code" do
    subject(:request) { delete_with_token(organization, "/api/v2/billable_metrics/#{metric.code}") }

    include_examples "requires API permission", "billable_metric", "write"

    it "soft deletes the metric and returns its deletion timestamp" do
      freeze_time do
        request

        expect(response).to have_http_status(:ok)
        expect(metric.reload).to be_discarded
        expect(json).to eq(billable_metric: expected_payload)
        expect(organization.billable_metrics.find_by(id: metric.id)).to be_nil
        expect(SendWebhookJob).to have_been_enqueued.with("billable_metric.deleted", metric)
      end
    end

    context "when the metric belongs to another organization" do
      let(:metric) { create(:billable_metric, organization: create(:organization)) }

      it "does not delete the foreign metric" do
        expect { request }.not_to change { metric.reload.deleted_at }

        expect(response).to be_v2_not_found_error("billable_metric")
      end
    end

    context "when the metric does not exist" do
      let(:metric) { build_stubbed(:billable_metric) }

      it "returns not found" do
        request

        expect(response).to be_v2_not_found_error("billable_metric")
      end
    end

    context "when a Product filter references the metric" do
      let(:filter) { create(:billable_metric_filter, billable_metric: metric, values: ["eu"]) }
      let(:product) { create(:product, organization:, billable_metric: metric) }
      let(:product_filter) { create(:product_filter, organization:, product:) }

      before { create(:product_filter_value, organization:, product_filter:, billable_metric_filter: filter, value: "eu") }

      it "preserves the metric" do
        expect { request }.not_to change { metric.reload.deleted_at }

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:details]).to eq([{code: "referenced_by_product_filter", field: "billable_metric", meta: {}}])
      end
    end
  end

  [[:get, ""], [:get, "/api.requests"], [:post, ""], [:put, "/api.requests"], [:patch, "/api.requests"], [:delete, "/api.requests"]].each do |method, suffix|
    describe "#{method.upcase} /api/v2/billable_metrics#{suffix} access" do
      subject(:request) { public_send(:"#{method}_with_token", organization, path, params) }

      let(:path) { "/api/v2/billable_metrics#{suffix}" }
      let(:params) { {} }

      it "requires authentication" do
        public_send(method, path)

        expect(response).to have_http_status(:unauthorized)
      end

      context "without Product Catalog", product_catalog: false do
        let(:organization) { create(:organization, feature_flags: []) }

        it "returns forbidden" do
          request

          expect(response).to have_http_status(:forbidden)
          expect(json[:code]).to eq("feature_unavailable")
        end
      end

      unless method == :get && suffix.present?
        context "with a filters expansion" do
          let(:params) { {expands: ["filters"]} }

          it "rejects expansions outside show" do
            expect { request }.not_to change(BillableMetric, :count)

            expect(response).to have_http_status(:bad_request)
            expect(json[:code]).to eq("expand_not_supported")
          end
        end
      end
    end
  end

  describe "POST /api/v2/billable_metrics/evaluate_expression", v2_timestamps: false do
    it "does not fall through to the v1 expression endpoint" do
      post_with_token(organization, "/api/v2/billable_metrics/evaluate_expression", expression: "1 + 1")

      expect(response).to have_http_status(:not_found)
      expect(json).to eq(code: "resource_not_found", details: [])
    end
  end
end
