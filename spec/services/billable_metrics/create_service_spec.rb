# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillableMetrics::CreateService do
  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:membership) { create(:membership) }

  describe "create" do
    let(:create_args) do
      {
        name: "New Metric",
        code: "new_metric",
        description: "New metric description",
        organization_id: organization.id,
        aggregation_type: "count_agg",
        expression: "1 + 2",
        rounding_function: "ceil",
        rounding_precision: 2,
        recurring: false
      }
    end

    it "creates a billable metric" do
      expect { described_class.call(create_args) }
        .to change(BillableMetric, :count).by(1)
    end

    it "enqueues a billable_metric.created webhook" do
      result = described_class.call(create_args)

      expect(SendWebhookJob).to have_been_enqueued.with("billable_metric.created", result.billable_metric)
    end

    it "expires the expression cache of the code" do
      cache_key = BillableMetrics::ExpressionCacheService.new(organization.id, create_args[:code]).cache_key
      allow(Rails.cache).to receive(:delete)

      described_class.call(create_args)

      expect(Rails.cache).to have_received(:delete).with(cache_key)
    end

    context "when an event was received for the code before the metric existed", cache: :memory do
      let(:create_args) do
        {
          name: "New Metric",
          code: "new_metric",
          organization_id: organization.id,
          aggregation_type: "sum_agg",
          field_name: "result",
          expression: "event.properties.left + event.properties.right"
        }
      end

      let(:event) do
        create(:event, organization:, code: create_args[:code], properties: {"left" => "1", "right" => "2"})
      end

      it "evaluates the expression on the following events" do
        # This caches the absence of an expression for the code
        Events::CalculateExpressionService.call(organization:, event:)

        described_class.call(create_args)

        result = Events::CalculateExpressionService.call(organization:, event:)
        expect(result.event.properties["result"]).to eq(3)
      end
    end

    context "with code already used by a deleted metric" do
      it "creates a billable metric with the same code" do
        create(:billable_metric, organization:, code: "new_metric", deleted_at: Time.current)

        expect { described_class.call(create_args) }
          .to change(BillableMetric, :count).by(1)

        metrics = organization.billable_metrics.with_discarded
        expect(metrics.count).to eq(2)
        expect(metrics.pluck(:code).uniq).to eq(["new_metric"])
      end
    end

    context "with filters arguments" do
      let(:create_args) do
        {
          name: "New Metric",
          code: "new_metric",
          description: "New metric description",
          organization_id: organization.id,
          aggregation_type: "count_agg",
          recurring: false,
          filters:
        }
      end

      let(:filters) do
        [
          {
            key: "cloud",
            values: %w[aws google]
          }
        ]
      end

      it "creates billable metric's filters" do
        expect { described_class.call(create_args) }
          .to change(BillableMetricFilter, :count).by(1)
      end

      context "with invalid filters" do
        let(:filters) { [{key: "foo"}] }

        it "returns an error if a filter is invalid" do
          result = described_class.call(create_args)

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:values]).to eq(["value_is_mandatory"])
        end
      end
    end

    it "calls SegmentTrackJob" do
      metric = described_class.call(create_args).billable_metric

      expect(SegmentTrackJob).to have_been_enqueued.with(
        membership_id: CurrentContext.membership,
        event: "billable_metric_created",
        properties: {
          code: metric.code,
          name: metric.name,
          description: metric.description,
          aggregation_type: metric.aggregation_type,
          aggregation_property: metric.field_name,
          organization_id: metric.organization_id
        }
      )
    end

    it "produces an activity log" do
      metric = described_class.call(create_args).billable_metric

      expect(Utils::ActivityLog).to have_produced("billable_metric.created").after_commit.with(metric)
    end

    context "with validation error" do
      before do
        create(
          :billable_metric,
          code: create_args[:code],
          organization: membership.organization
        )
      end

      it "returns an error" do
        result = described_class.call(create_args)

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:code]).to eq(["value_already_exist"])
      end
    end

    context "with custom aggregation" do
      let(:create_args) do
        {
          name: "New Metric",
          code: "new_metric",
          description: "New metric description",
          organization_id: organization.id,
          aggregation_type: "custom_agg",
          recurring: false
        }
      end

      it "returns a forbidden failure" do
        result = described_class.call(create_args)

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
      end
    end
  end
end
