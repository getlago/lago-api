# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillableMetrics::UpdateService, type: :service do
  subject(:update_service) { described_class.new(billable_metric:, params:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:params) do
    {
      name: "New Metric",
      code: "new_metric",
      description: "New metric description",
      aggregation_type: "sum_agg",
      field_name: "field_value"
    }.tap do |p|
      p[:group] = group unless group.nil?
      p[:filters] = filters unless filters.nil?
    end
  end
  let(:group) { nil }
  let(:filters) { nil }

  describe "#call" do
    it "updates the billable metric" do
      result = update_service.call

      aggregate_failures do
        expect(result).to be_success

        metric = result.billable_metric
        expect(metric.id).to eq(billable_metric.id)
        expect(metric.name).to eq("New Metric")
        expect(metric.code).to eq("new_metric")
        expect(metric.aggregation_type).to eq("sum_agg")
      end
    end

    context "with group parameter" do
      let(:group) do
        {
          key: "cloud",
          values: [
            {name: "AWS", key: "region", values: %w[usa europe]},
            {name: "Google", key: "region", values: ["usa"]}
          ]
        }
      end

      it "updates billable metric's group" do
        expect { update_service.call }.to change { billable_metric.active_groups.reload.count }.from(0).to(5)
      end

      context "with empty group" do
        let(:group) { {} }

        before { create(:group, billable_metric:) }

        it "updates billable metric's group" do
          expect { update_service.call }.to change { billable_metric.active_groups.reload.count }.from(1).to(0)
        end
      end

      context "with invalid group" do
        let(:group) { {key: 1} }

        it "returns an error if group is invalid" do
          result = update_service.call

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages[:group]).to eq(["value_is_invalid"])
          end
        end
      end
    end

    context "with filters arguments" do
      let(:filters) do
        [
          {
            key: "cloud",
            values: %w[aws google]
          }
        ]
      end

      it "updates billable metric's filters" do
        expect { update_service.call }.to change { billable_metric.filters.reload.count }.from(0).to(1)
      end
    end

    context "with validation errors" do
      let(:params) do
        {
          name: nil,
          code: "new_metric",
          description: "New metric description",
          aggregation_type: "count_agg"
        }
      end

      it "returns an error" do
        result = update_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:name]).to eq(["value_is_mandatory"])
        end
      end
    end

    context "when billable metric is not found" do
      let(:billable_metric) { nil }

      it "returns an error" do
        result = update_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.error_code).to eq("billable_metric_not_found")
        end
      end
    end

    context "when billable metric is linked to plan" do
      let(:plan) { create(:plan, organization:) }
      let(:charge) { create(:standard_charge, billable_metric:, plan:) }

      before { charge }

      it "updates only name and description" do
        result = update_service.call

        aggregate_failures do
          expect(result).to be_success

          expect(result.billable_metric).to have_attributes(
            name: "New Metric",
            description: "New metric description"
          )

          expect(result.billable_metric).not_to have_attributes(
            code: "new_metric",
            aggregation_type: "sum_agg",
            field_name: "field_value"
          )
        end
      end
    end
  end
end
