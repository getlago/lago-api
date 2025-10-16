# frozen_string_literal: true

require "rails_helper"

RSpec.describe Plans::UpdateNotificationMiddleware do
  subject(:middleware) do
    described_class.new(service_instance, next_middleware, *args, **kwargs)
  end

  let(:service_class) do
    Class.new(BaseService) do
      const_set(:Result, BaseResult[:plan])

      def initialize(plan:)
        @plan = plan
        super()
      end

      def call(&block)
        result.plan = plan
        result
      end

      private

      attr_reader :plan
    end
  end

  let(:organization) { create(:organization, premium_integrations:) }
  let(:plan) { create(:plan, organization:) }
  let(:charges) { create_list(:standard_charge, 3, plan:, organization:) }

  let(:service_instance) { service_class.new(plan:) }
  let(:next_middleware) { lambda { plan } }
  let(:args) { [] }
  let(:kwargs) { {plan: lambda { plan }} }

  let(:premium_integrations) { [] }

  before { charges }

  describe ".call" do
    context "with Kafka config", :premium do
      let(:premium_integrations) { ["clickhouse_live_aggregation"] }

      before do
        ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"] = "kafka"
        ENV["LAGO_KAFKA_PLAN_CONFIG_UPDATED_TOPIC"] = "plan_config_updated"
      end

      it "creates an initial snapshot of the plan" do
        middleware.call

        snapshot = middleware.instance_variable_get(:@snapshot)
        expect(snapshot).not_to be_nil
        expect(snapshot).to eq(charges.map { {id: it.id, pricing_group_keys: nil, filters: []} })
      end

      context "when clickhouse live aggregation is not enabled" do
        let(:premium_integrations) { [] }

        it "does not create a snapshot" do
          middleware.call

          snapshot = middleware.instance_variable_get(:@snapshot)
          expect(snapshot).to be_nil
        end
      end

      context "when a charge is removed" do
        let(:next_middleware) {
          lambda {
            charge.destroy
            BaseResult[:plan].new.tap { it.plan = plan.reload }
          }
        }
        let(:charge) { plan.charges.last }

        before do
          allow(Plans::UpdatedKafkaProducerService).to receive(:call!)
        end

        it "notify the removal of the charge" do
          middleware.call

          expect(Plans::UpdatedKafkaProducerService)
            .to have_received(:call!)
            .with(
              plan:,
              resources_type: "charge",
              resources_ids: [charge.id],
              event_type: "charges.deleted",
              timestamp: plan.updated_at
            )
        end
      end

      context "when a charge is added" do
        let(:next_middleware) {
          lambda {
            charge
            BaseResult[:plan].new.tap { it.plan = plan.reload }
          }
        }
        let(:charge) { create(:standard_charge, plan:) }

        before do
          allow(Plans::UpdatedKafkaProducerService).to receive(:call!)
        end

        it "notify the removal of the charge" do
          middleware.call

          expect(Plans::UpdatedKafkaProducerService)
            .to have_received(:call!)
            .with(
              plan:,
              resources_type: "charge",
              resources_ids: [charge.id],
              event_type: "charges.created",
              timestamp: plan.updated_at
            )
        end
      end

      context "when a pricing group key is added to the charge" do
        let(:next_middleware) {
          lambda {
            charge.properties["pricing_group_keys"] = ["country"]
            charge.save!
            BaseResult[:plan].new.tap { it.plan = plan.reload }
          }
        }
        let(:charge) { plan.charges.last }

        before do
          allow(Plans::UpdatedKafkaProducerService).to receive(:call!)
        end

        it "notify the update of the pricing group keys" do
          middleware.call

          expect(Plans::UpdatedKafkaProducerService)
            .to have_received(:call!)
            .with(
              plan:,
              resources_type: "charge",
              resources_ids: [charge.id],
              event_type: "charges.pricing_group_keys_updated",
              timestamp: plan.updated_at
            )
        end
      end

      context "when a pricing group key is removed from the charge" do
        let(:next_middleware) {
          lambda {
            charge.properties["pricing_group_keys"] = ["country"]
            charge.save!
            BaseResult[:plan].new.tap { it.plan = plan.reload }
          }
        }
        let(:charge) do
          charge = plan.charges.last
          charge.properties["pricing_group_keys"] = ["country", "region"]
          charge.save!
          charge
        end

        before do
          allow(Plans::UpdatedKafkaProducerService).to receive(:call!)
        end

        it "notify the update of the pricing group keys" do
          middleware.call

          expect(Plans::UpdatedKafkaProducerService)
            .to have_received(:call!)
            .with(
              plan:,
              resources_type: "charge",
              resources_ids: [charge.id],
              event_type: "charges.pricing_group_keys_updated",
              timestamp: plan.updated_at
            )
        end
      end

      context "when a pricing group key is changed" do
        let(:next_middleware) {
          lambda {
            charge.properties["pricing_group_keys"] = ["zone"]
            charge.save!
            BaseResult[:plan].new.tap { it.plan = plan.reload }
          }
        }
        let(:charge) do
          charge = plan.charges.last
          charge.properties["pricing_group_keys"] = ["country"]
          charge.save!
          charge
        end

        before do
          allow(Plans::UpdatedKafkaProducerService).to receive(:call!)
        end

        it "notify the update of the pricing group keys" do
          middleware.call

          expect(Plans::UpdatedKafkaProducerService)
            .to have_received(:call!)
            .with(
              plan:,
              resources_type: "charge",
              resources_ids: [charge.id],
              event_type: "charges.pricing_group_keys_updated",
              timestamp: plan.updated_at
            )
        end
      end

      context "when a filter is added to the charge" do
        let(:next_middleware) {
          lambda {
            charge_filter_value
            BaseResult[:plan].new.tap { it.plan = plan.reload }
          }
        }
        let(:charge) { plan.charges.last }
        let(:charge_filter) { create(:charge_filter, charge:, organization:) }
        let(:charge_filter_value) { create(:charge_filter_value, charge_filter:, values: ["aws"], billable_metric_filter:) }

        let(:billable_metric) { charge.billable_metric }
        let(:billable_metric_filter) do
          create(:billable_metric_filter, billable_metric:, organization:, values: ["aws", "gcp", "azure"])
        end

        before do
          allow(Plans::UpdatedKafkaProducerService).to receive(:call!)
        end

        it "notify the removal of the charge" do
          middleware.call

          expect(Plans::UpdatedKafkaProducerService)
            .to have_received(:call!)
            .with(
              plan:,
              resources_type: "charge",
              resources_ids: [charge.id],
              event_type: "charges.updated",
              timestamp: plan.updated_at
            )
        end
      end

      context "when a filter is removed from the charge" do
        let(:next_middleware) {
          lambda {
            charge_filter.destroy!
            BaseResult[:plan].new.tap { it.plan = plan.reload }
          }
        }
        let(:charge) { plan.charges.last }
        let(:charge_filter) { create(:charge_filter, charge:, organization:) }
        let(:charge_filter_value) { create(:charge_filter_value, charge_filter:, values: ["aws"], billable_metric_filter:) }

        let(:billable_metric) { charge.billable_metric }
        let(:billable_metric_filter) do
          create(:billable_metric_filter, billable_metric:, organization:, values: ["aws", "gcp", "azure"])
        end

        before do
          allow(Plans::UpdatedKafkaProducerService).to receive(:call!)
          charge_filter_value
        end

        it "notify the removal of the charge" do
          middleware.call

          expect(Plans::UpdatedKafkaProducerService)
            .to have_received(:call!)
            .with(
              plan:,
              resources_type: "charge",
              resources_ids: [charge.id],
              event_type: "charges.updated",
              timestamp: plan.updated_at
            )
        end
      end

      context "when filters are changed on the charge" do
        let(:next_middleware) {
          lambda {
            charge_filter1.destroy!
            charge_filter_value2
            BaseResult[:plan].new.tap { it.plan = plan.reload }
          }
        }
        let(:charge) { plan.charges.last }
        let(:billable_metric) { charge.billable_metric }
        let(:billable_metric_filter) do
          create(:billable_metric_filter, billable_metric:, organization:, values: ["aws", "gcp", "azure"])
        end

        let(:charge_filter1) { create(:charge_filter, charge:, organization:) }
        let(:charge_filter_value1) { create(:charge_filter_value, charge_filter: charge_filter1, values: ["aws"], billable_metric_filter:) }

        let(:charge_filter2) { create(:charge_filter, charge:, organization:) }
        let(:charge_filter_value2) { create(:charge_filter_value, charge_filter: charge_filter2, values: ["gcp"], billable_metric_filter:) }

        before do
          allow(Plans::UpdatedKafkaProducerService).to receive(:call!)
          charge_filter_value1
        end

        it "notify the removal of the charge" do
          middleware.call

          expect(Plans::UpdatedKafkaProducerService)
            .to have_received(:call!)
            .with(
              plan:,
              resources_type: "charge",
              resources_ids: [charge.id],
              event_type: "charges.updated",
              timestamp: plan.updated_at
            )
        end
      end

      context "when filters are changed on the charge but not values" do
        let(:next_middleware) {
          lambda {
            charge_filter1.destroy!
            charge_filter_value2
            BaseResult[:plan].new.tap { it.plan = plan.reload }
          }
        }
        let(:charge) { plan.charges.last }
        let(:billable_metric) { charge.billable_metric }
        let(:billable_metric_filter) do
          create(:billable_metric_filter, billable_metric:, organization:, values: ["aws", "gcp", "azure"])
        end

        let(:charge_filter1) { create(:charge_filter, charge:, organization:) }
        let(:charge_filter_value1) { create(:charge_filter_value, charge_filter: charge_filter1, values: ["aws"], billable_metric_filter:) }

        let(:charge_filter2) { create(:charge_filter, charge:, organization:) }
        let(:charge_filter_value2) { create(:charge_filter_value, charge_filter: charge_filter2, values: ["aws"], billable_metric_filter:) }

        before do
          allow(Plans::UpdatedKafkaProducerService).to receive(:call!)
          charge_filter_value1
        end

        it "notify the removal of the charge" do
          middleware.call

          expect(Plans::UpdatedKafkaProducerService)
            .to have_received(:call!)
            .with(
              plan:,
              resources_type: "charge",
              resources_ids: [charge.id],
              event_type: "charges.updated",
              timestamp: plan.updated_at
            )
        end
      end

      context "when filter's pricing group keys is changed" do
        let(:next_middleware) {
          lambda {
            charge_filter.properties["pricing_group_keys"] = ["zone"]
            charge_filter.save!
            BaseResult[:plan].new.tap { it.plan = plan.reload }
          }
        }
        let(:charge) { plan.charges.last }
        let(:charge_filter) { create(:charge_filter, charge:, organization:) }

        before do
          allow(Plans::UpdatedKafkaProducerService).to receive(:call!)
          charge_filter
        end

        it "notify the removal of the charge" do
          middleware.call

          expect(Plans::UpdatedKafkaProducerService)
            .to have_received(:call!)
            .with(
              plan:,
              resources_type: "charge_filter",
              resources_ids: [charge_filter.id],
              event_type: "charge_filters.pricing_group_keys_updated",
              timestamp: plan.updated_at
            )
        end
      end
    end

    context "when not premium" do
      it "does not create a snapshot" do
        middleware.call

        snapshot = middleware.instance_variable_get(:@snapshot)
        expect(snapshot).to be_nil
      end
    end

    context "without Kafka config", :premium do
      it "does not create a snapshot" do
        middleware.call

        snapshot = middleware.instance_variable_get(:@snapshot)
        expect(snapshot).to be_nil
      end
    end
  end
end
