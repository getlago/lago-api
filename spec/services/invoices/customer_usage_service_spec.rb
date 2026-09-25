# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::CustomerUsageService, cache: :memory do
  subject(:usage_service) do
    described_class.with_ids(
      organization_id: membership.organization_id,
      customer_id:,
      subscription_id:,
      apply_taxes:
    )
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:tax) { create(:tax, :applied_to_billing_entity, organization:, rate: 20) }
  let(:customer) { create(:customer, organization:) }
  let(:customer_id) { customer&.id }
  let(:subscription_id) { subscription&.id }
  let(:plan) { create(:plan, organization:, interval: "monthly") }
  let(:timestamp) { Time.current }
  let(:apply_taxes) { true }

  let(:subscription) do
    create(
      :subscription,
      plan:,
      customer:,
      started_at: Time.zone.now - 2.years
    )
  end

  let(:billable_metric) do
    create(:billable_metric, aggregation_type: "count_agg")
  end

  let(:charge) do
    create(
      :standard_charge,
      plan:,
      billable_metric:,
      properties: {amount: "12.66"}
    )
  end

  # created_at predates the aggregation: CacheService refuses to store a value whose watermark is
  # younger than SETTLE_WINDOW, so freshly ingested events would never populate the charge cache.
  let(:events) do
    create_list(
      :event,
      2,
      organization:,
      subscription:,
      customer:,
      code: billable_metric.code,
      timestamp:,
      created_at: 1.hour.ago
    )
  end

  describe "#call" do
    before do
      events if subscription
      charge
      Rails.cache.clear

      tax
    end

    it "uses the Rails cache" do
      key = [
        "charge-usage",
        Subscriptions::ChargeCacheService::CACHE_KEY_VERSION,
        charge.id,
        subscription.id,
        charge.updated_at.iso8601
      ].join("/")

      expect do
        usage_service.call
      end.to change { Rails.cache.exist?(key) }.from(false).to(true)
    end

    it "does not query AdjustedFee and skips adjusted fees" do
      allow(AdjustedFee).to receive(:matching_charge_boundaries).and_call_original
      allow(Fees::ChargeService).to receive(:call!).and_call_original
      usage_service.call

      expect(AdjustedFee).not_to have_received(:matching_charge_boundaries)
      expect(Fees::ChargeService).to have_received(:call!)
        .with(hash_including(options: have_attributes(skip_adjusted_fees: true)))
    end

    context "when initializes an invoice" do
      let(:current_date) { DateTime.parse("2025-06-15") }
      let(:timestamp) { current_date }

      it "initializes an invoice" do
        travel_to(current_date) do
          result = usage_service.call

          expect(result).to be_success
          expect(result.invoice).to be_a(Invoice)
          expect(result.invoice.organization).to eq(organization)
          expect(result.invoice.billing_entity).to eq(customer.billing_entity)
          expect(result.invoice.total_paid_amount_cents).to eq(0)
          expect(result.invoice.prepaid_credit_amount_cents).to eq(0)

          expect(result.usage).to have_attributes(
            from_datetime: Time.current.beginning_of_month.iso8601,
            to_datetime: Time.current.end_of_month.iso8601,
            issuing_date: Time.zone.today.end_of_month.iso8601,
            currency: "EUR",
            amount_cents: 2532, # 1266 * 2,
            taxes_amount_cents: 506, # 1266 * 2 * 0.2 = 506.4
            total_amount_cents: 3038
          )
          expect(result.usage.fees.size).to eq(1)
          expect(result.usage.fees.first.charge.invoice_display_name).to eq(charge.invoice_display_name)
        end
      end
    end

    context "when apply_taxes property is set to false" do
      let(:current_date) { DateTime.parse("2025-06-15") }
      let(:timestamp) { current_date }
      let(:apply_taxes) { false }

      it "initializes an invoice" do
        travel_to(current_date) do
          result = usage_service.call

          expect(result).to be_success
          expect(result.invoice).to be_a(Invoice)

          expect(result.usage).to have_attributes(
            from_datetime: Time.current.beginning_of_month.iso8601,
            to_datetime: Time.current.end_of_month.iso8601,
            issuing_date: Time.zone.today.end_of_month.iso8601,
            currency: "EUR",
            amount_cents: 2532, # 1266 * 2,
            taxes_amount_cents: 0,
            total_amount_cents: 2532
          )
          expect(result.usage.fees.size).to eq(1)
          expect(result.usage.fees.first.charge.invoice_display_name).to eq(charge.invoice_display_name)
        end
      end
    end

    context "when there is tax provider integration" do
      let(:integration) { create(:anrok_integration, organization:) }
      let(:integration_customer) { create(:anrok_customer, integration:, customer:) }
      let(:endpoint) { "https://api.nango.dev/v1/anrok/draft_invoices" }
      let(:integration_collection_mapping) do
        create(
          :netsuite_collection_mapping,
          integration:,
          mapping_type: :fallback_item,
          settings: {external_id: "1", external_account_code: "11", external_name: ""}
        )
      end

      before do
        integration_collection_mapping
        integration_customer
      end

      context "when there is no error" do
        let(:current_date) { DateTime.parse("2025-06-15") }
        let(:timestamp) { current_date }

        before do
          stub_request(:post, endpoint).to_return do |request|
            response = JSON.parse(File.read(
              Rails.root.join("spec/fixtures/integration_aggregator/taxes/invoices/success_response.json")
            ))

            # setting item_id based on the test example
            key = JSON.parse(request.body).first["fees"].last["item_key"]
            response["succeededInvoices"].first["fees"].last["item_key"] = key
            response["succeededInvoices"].first["fees"].last["item_id"] = charge.billable_metric.id
            response["succeededInvoices"].first["fees"].last["amount_cents"] = 2532

            {body: response.to_json}
          end
        end

        it "initializes an invoice" do
          travel_to(current_date) do
            result = usage_service.call

            expect(result).to be_success
            expect(result.invoice).to be_a(Invoice)

            expect(result.usage).to have_attributes(
              from_datetime: Time.current.beginning_of_month.iso8601,
              to_datetime: Time.current.end_of_month.iso8601,
              issuing_date: Time.zone.today.end_of_month.iso8601,
              currency: "EUR",
              amount_cents: 2532, # 1266 * 2,
              taxes_amount_cents: 253, # 2532 * 0.1
              total_amount_cents: 2785
            )
            expect(result.usage.fees.size).to eq(1)
            expect(result.usage.fees.first.charge.invoice_display_name).to eq(charge.invoice_display_name)
          end
        end
      end

      context "when a charge produces a zero fee" do
        let(:current_date) { DateTime.parse("2025-06-15") }
        let(:timestamp) { current_date }
        let(:empty_metric) { create(:billable_metric, organization:, aggregation_type: "count_agg") }
        let(:empty_charge) { create(:standard_charge, plan:, billable_metric: empty_metric, properties: {amount: "5"}) }
        # Free usage: has events and units but a zero amount, so it is non_zero? but not taxable?
        let(:free_metric) { create(:billable_metric, organization:, aggregation_type: "count_agg") }
        let(:free_charge) { create(:standard_charge, plan:, billable_metric: free_metric, properties: {amount: "0"}) }

        before do
          empty_charge
          free_charge
          create_list(:event, 2, organization:, subscription:, customer:, code: free_metric.code, timestamp:)
          allow(Integrations::Aggregator::Taxes::Invoices::CreateDraftService).to receive(:call).and_call_original

          stub_request(:post, endpoint).to_return do |request|
            response = JSON.parse(File.read(
              Rails.root.join("spec/fixtures/integration_aggregator/taxes/invoices/success_response.json")
            ))

            key = JSON.parse(request.body).first["fees"].last["item_key"]
            response["succeededInvoices"].first["fees"].last["item_key"] = key
            response["succeededInvoices"].first["fees"].last["item_id"] = charge.billable_metric.id
            response["succeededInvoices"].first["fees"].last["amount_cents"] = 2532

            {body: response.to_json}
          end
        end

        it "keeps the non-taxable fees in the usage but excludes them from the tax provider payload" do
          travel_to(current_date) do
            result = usage_service.call

            expect(result).to be_success
            # both zero-amount fees (empty + free usage) stay in the usage response
            expect(result.usage.fees.map(&:amount_cents)).to match_array([0, 0, 2532])
            # only the taxable (positive-amount) fee is sent to the provider
            expect(Integrations::Aggregator::Taxes::Invoices::CreateDraftService).to have_received(:call) do |invoice:, fees:|
              expect(fees.map(&:amount_cents)).to match_array([2532])
            end
          end
        end

        it "leaves the excluded non-taxable fees with default zero taxes" do
          travel_to(current_date) do
            result = usage_service.call

            non_taxable_fees = result.usage.fees.reject(&:taxable?)
            expect(non_taxable_fees.size).to eq(2)
            non_taxable_fees.each do |fee|
              expect(fee.taxes_amount_cents).to eq(0)
              expect(fee.taxes_rate).to eq(0)
              expect(fee.applied_taxes).to be_empty
            end
          end
        end

        it "computes the invoice taxes_rate without diluting it by the excluded fees" do
          travel_to(current_date) do
            result = usage_service.call

            # The rate is prorated by amount over the taxable fee only (10%), not by fee
            # count over all three fees, which would dilute it to 1/3 * 10 = 3.33%.
            expect(result.invoice.taxes_rate).to eq(10)
            expect(result.usage.taxes_amount_cents).to eq(253)
          end
        end
      end

      context "when there are no taxable fees" do
        # The single charge produces a zero-amount fee, so taxable_fees is empty.
        let(:charge) { create(:standard_charge, plan:, billable_metric:, properties: {amount: "0"}) }

        before do
          allow(Integrations::Aggregator::Taxes::Invoices::CreateDraftService).to receive(:call)
        end

        it "skips the provider request and returns a zero-tax usage" do
          result = usage_service.call

          expect(result).to be_success
          expect(Integrations::Aggregator::Taxes::Invoices::CreateDraftService).not_to have_received(:call)
          expect(result.usage).to have_attributes(
            amount_cents: 0,
            taxes_amount_cents: 0,
            total_amount_cents: 0
          )
        end

        it "leaves the zero fee with default zero taxes" do
          result = usage_service.call

          fee = result.usage.fees.sole
          expect(fee.taxes_amount_cents).to eq(0)
          expect(fee.taxes_rate).to eq(0)
          expect(fee.applied_taxes).to be_empty
        end
      end

      context "when there is error received from the provider" do
        before do
          stub_request(:post, endpoint).to_return do |request|
            response = File.read(
              Rails.root.join("spec/fixtures/integration_aggregator/taxes/invoices/failure_response.json")
            )
            {body: response}
          end
        end

        it "returns tax error" do
          result = usage_service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:tax_error]).to eq(["taxDateTooFarInFuture: Service failure"])
        end
      end
    end

    context "with subscription started in current billing period" do
      before { subscription.update!(started_at: Time.zone.today) }

      it "changes the from date of the invoice" do
        result = usage_service.call

        expect(result).to be_success
        expect(result.usage.from_datetime).to eq(subscription.started_at.iso8601)
      end
    end

    context "when subscription is billed on anniversary date" do
      let(:current_date) { DateTime.parse("2022-06-22") }
      let(:started_at) { DateTime.parse("2022-03-07") }
      let(:subscription_at) { started_at }
      let(:timestamp) { current_date }

      let(:subscription) do
        create(
          :subscription,
          plan:,
          customer:,
          subscription_at:,
          started_at:,
          billing_time: :anniversary
        )
      end

      it "initializes an invoice" do
        travel_to(current_date) do
          result = usage_service.call

          expect(result).to be_success
          expect(result.invoice).to be_a(Invoice)

          expect(result.usage).to have_attributes(
            issuing_date: "2022-07-06",
            currency: "EUR",
            amount_cents: 2532, # 1266 * 2,
            taxes_amount_cents: 506, # 1266 * 2 * 0.2 = 506.4
            total_amount_cents: 3038
          )

          expect(result.usage.from_datetime.to_date.to_s).to eq("2022-06-07")
          expect(result.usage.to_datetime.to_date.to_s).to eq("2022-07-06")
          expect(result.usage.fees.size).to eq(1)
        end
      end
    end

    context "when customer is not found" do
      let(:customer_id) { "foo" }

      it "returns an error" do
        result = usage_service.call

        expect(result).not_to be_success
        expect(result.error.error_code).to eq("customer_not_found")
      end
    end

    context "when no_active_subscription" do
      let(:subscription) { nil }

      it "fails" do
        result = usage_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
        expect(result.error.code).to eq("no_active_subscription")
      end
    end

    context "with filter_by_charge_id" do
      subject(:usage_service) do
        described_class.new(
          customer:,
          subscription:,
          apply_taxes: false,
          with_cache: false,
          usage_filters: UsageFilters.new(filter_by_charge_id: charge.id)
        )
      end

      let(:billable_metric_2) { create(:billable_metric, aggregation_type: "count_agg") }

      let(:charge_2) do
        create(:standard_charge, plan:, billable_metric: billable_metric_2, properties: {amount: "5"})
      end

      let(:events_2) do
        create_list(:event, 3, organization:, subscription:, customer:, code: billable_metric_2.code, timestamp:)
      end

      before do
        events_2
        charge_2
      end

      it "returns fees only for the specified charge" do
        result = usage_service.call

        expect(result).to be_success
        expect(result.usage.fees.map(&:charge_id).uniq).to eq([charge.id])
      end
    end

    context "with filter_by_charge_code" do
      subject(:usage_service) do
        described_class.new(
          customer:,
          subscription:,
          apply_taxes: false,
          with_cache: false,
          usage_filters: UsageFilters.new(filter_by_charge_code: charge.code)
        )
      end

      let(:billable_metric_2) { create(:billable_metric, aggregation_type: "count_agg") }

      let(:charge_2) do
        create(:standard_charge, plan:, billable_metric: billable_metric_2, properties: {amount: "5"})
      end

      let(:events_2) do
        create_list(:event, 3, organization:, subscription:, customer:, code: billable_metric_2.code, timestamp:)
      end

      before do
        events_2
        charge_2
      end

      it "returns fees only for the specified charge" do
        result = usage_service.call

        expect(result).to be_success
        expect(result.usage.fees.map(&:charge_id).uniq).to eq([charge.id])
      end
    end

    context "with filter_by_group" do
      subject(:usage_service) do
        described_class.new(
          customer:,
          subscription:,
          apply_taxes: false,
          with_cache: false,
          usage_filters: UsageFilters.new(filter_by_group: {"cloud" => ["aws"]})
        )
      end

      let(:billable_metric) do
        create(:billable_metric, aggregation_type: "sum_agg", field_name: "value")
      end

      let(:charge) do
        create(
          :standard_charge,
          plan:,
          billable_metric:,
          properties: {amount: "10", pricing_group_keys: %w[cloud]}
        )
      end

      let(:events) { [] }

      before do
        create(:event, organization:, subscription:, customer:, code: billable_metric.code,
          timestamp:, properties: {cloud: "aws", value: 10})
        create(:event, organization:, subscription:, customer:, code: billable_metric.code,
          timestamp:, properties: {cloud: "gcp", value: 5})
      end

      it "returns fees filtered by the group" do
        result = usage_service.call

        expect(result).to be_success
        expect(result.usage.fees.size).to eq(1)
        expect(result.usage.fees.first.units).to eq(10)
      end
    end

    context "with full_usage" do
      let(:billable_metric) do
        create(:billable_metric, aggregation_type: "count_agg")
      end

      let(:charge) do
        create(:standard_charge, plan:, billable_metric:, properties: {amount: "10"})
      end

      let(:events) { [] }

      context "when organization does not have lifetime_usage enabled", :premium do
        subject(:usage_service) do
          described_class.new(
            customer:,
            subscription:,
            apply_taxes: false,
            with_cache: false,
            usage_filters: UsageFilters.new(filter_by_charge_id: charge.id, full_usage: true)
          )
        end

        it "returns a not_allowed failure" do
          result = usage_service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
          expect(result.error.code).to eq("full_usage_not_allowed")
        end
      end

      context "when granular_lifetime_usage is enabled", :premium do
        let(:current_usage_cache_key) do
          Subscriptions::ChargeCacheService.new(subscription:, charge:).cache_key
        end

        let(:full_usage_cache_key) do
          Subscriptions::ChargeCacheService.new(subscription:, charge:, full_usage: true).cache_key
        end

        before { organization.update!(premium_integrations: %w[granular_lifetime_usage]) }

        context "when filter_by_charge_id is provided and no prorated charges" do
          subject(:usage_service) do
            described_class.new(
              customer:,
              subscription:,
              apply_taxes: false,
              with_cache: false,
              usage_filters: UsageFilters.new(filter_by_charge_id: charge.id, full_usage: true)
            )
          end

          before do
            create_list(:event, 2, organization:, subscription:, customer:, code: billable_metric.code, timestamp:)
          end

          it "returns usage successfully" do
            result = usage_service.call

            expect(result).to be_success
            expect(result.usage.fees.size).to eq(1)
          end
        end

        context "when filter_by_charge_code is provided and no prorated charges" do
          subject(:usage_service) do
            described_class.new(
              customer:,
              subscription:,
              apply_taxes: false,
              with_cache: false,
              usage_filters: UsageFilters.new(filter_by_charge_code: charge.code, full_usage: true)
            )
          end

          before do
            create_list(:event, 2, organization:, subscription:, customer:, code: billable_metric.code, timestamp:)
          end

          it "returns usage successfully" do
            result = usage_service.call

            expect(result).to be_success
            expect(result.usage.fees.size).to eq(1)
          end
        end

        context "when no filter is provided" do
          subject(:usage_service) do
            described_class.new(
              customer:,
              subscription:,
              apply_taxes: false,
              with_cache: false,
              usage_filters: UsageFilters.new(full_usage: true)
            )
          end

          before do
            create_list(:event, 2, organization:, subscription:, customer:, code: billable_metric.code, timestamp:)
          end

          it "returns a not_allowed failure" do
            result = usage_service.call

            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
            expect(result.error.code).to eq("full_usage_not_allowed")
          end
        end

        context "when a different charge is prorated but filtered charge is not" do
          subject(:usage_service) do
            described_class.new(
              customer:,
              subscription:,
              apply_taxes: false,
              with_cache: false,
              usage_filters: UsageFilters.new(filter_by_charge_id: charge.id, full_usage: true)
            )
          end

          let(:prorated_metric) { create(:billable_metric, :recurring, organization:, aggregation_type: "sum_agg", field_name: "value") }
          let(:prorated_charge) do
            create(:standard_charge, plan:, billable_metric: prorated_metric, prorated: true, properties: {amount: "5"})
          end

          before do
            prorated_charge
            create_list(:event, 2, organization:, subscription:, customer:, code: billable_metric.code, timestamp:)
          end

          it "returns usage successfully" do
            result = usage_service.call

            expect(result).to be_success
            expect(result.usage.fees.size).to eq(1)
          end
        end

        context "when the filtered charge itself is prorated" do
          subject(:usage_service) do
            described_class.new(
              customer:,
              subscription:,
              apply_taxes: false,
              with_cache: false,
              usage_filters: UsageFilters.new(filter_by_charge_id: prorated_charge.id, full_usage: true)
            )
          end

          let(:prorated_metric) { create(:billable_metric, :recurring, organization:, aggregation_type: "sum_agg", field_name: "value") }
          let(:prorated_charge) do
            create(:standard_charge, plan:, billable_metric: prorated_metric, prorated: true, properties: {amount: "5"})
          end

          before do
            prorated_charge
            create_list(:event, 2, organization:, subscription:, customer:, code: prorated_metric.code, timestamp:)
          end

          it "returns a not_allowed failure" do
            result = usage_service.call

            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
            expect(result.error.code).to eq("full_usage_not_allowed")
          end
        end

        context "when subscription started at current period boundary" do
          subject(:usage_service) do
            described_class.new(
              customer:,
              subscription:,
              apply_taxes: false,
              with_cache: true,
              usage_filters: UsageFilters.new(filter_by_charge_id: charge.id, full_usage: true)
            )
          end

          let(:current_date) { DateTime.parse("2025-06-15") }
          let(:timestamp) { current_date }

          let(:subscription) do
            create(:subscription, plan:, customer:, started_at: DateTime.parse("2025-06-01"))
          end

          # created_at predates the aggregation: CacheService refuses to store a value whose
          # watermark is younger than SETTLE_WINDOW.
          before do
            create_list(:event, 2, organization:, subscription:, customer:,
              code: billable_metric.code, timestamp:, created_at: current_date - 1.hour)
          end

          # The windows are identical here, but started_at is editable, so the entry is still not shared.
          it "uses the full usage cache entry, not the current usage one" do
            travel_to(current_date) do
              expect { usage_service.call }
                .to change { Rails.cache.exist?(full_usage_cache_key) }.from(false).to(true)

              expect(Rails.cache.exist?(current_usage_cache_key)).to be(false)
            end
          end
        end

        context "when subscription started before current period" do
          subject(:usage_service) do
            described_class.new(
              customer:,
              subscription:,
              apply_taxes: false,
              with_cache: true,
              usage_filters: UsageFilters.new(filter_by_charge_id: charge.id, full_usage: true)
            )
          end

          let(:current_date) { DateTime.parse("2025-06-15") }
          let(:timestamp) { current_date }

          let(:subscription) do
            create(:subscription, plan:, customer:, started_at: DateTime.parse("2025-03-01"))
          end

          before do
            create_list(:event, 2, organization:, subscription:, customer:,
              code: billable_metric.code, timestamp:, created_at: current_date - 1.hour)
          end

          it "uses the full usage cache entry, not the current usage one" do
            travel_to(current_date) do
              expect { usage_service.call }
                .to change { Rails.cache.exist?(full_usage_cache_key) }.from(false).to(true)

              expect(Rails.cache.exist?(current_usage_cache_key)).to be(false)
            end
          end
        end
      end
    end

    context "with skip_grouping" do
      subject(:usage_service) do
        described_class.new(
          customer:,
          subscription:,
          apply_taxes: false,
          with_cache: false,
          usage_filters: UsageFilters.new(skip_grouping: true)
        )
      end

      let(:billable_metric) do
        create(:billable_metric, aggregation_type: "sum_agg", field_name: "value")
      end

      let(:charge) do
        create(
          :standard_charge,
          plan:,
          billable_metric:,
          properties: {amount: "10", pricing_group_keys: %w[cloud]}
        )
      end

      let(:events) { [] }

      before do
        create(:event, organization:, subscription:, customer:, code: billable_metric.code,
          timestamp:, properties: {cloud: "aws", value: 10})
        create(:event, organization:, subscription:, customer:, code: billable_metric.code,
          timestamp:, properties: {cloud: "gcp", value: 5})
      end

      it "returns a single fee with all events aggregated without grouping" do
        result = usage_service.call

        expect(result).to be_success
        expect(result.usage.fees.size).to eq(1)
        expect(result.usage.fees.first.units).to eq(15)
        expect(result.usage.fees.first.grouped_by).to eq({})
      end
    end

    # The charge cache is lazily invalidated with the ingestion timestamps requested by
    # Events::BillingPeriodFilterService, so a cached charge must always have asked for them:
    # an entry stored without a timestamp stays valid for the rest of the billing period, for
    # every later reader. Each example asserts both halves so they cannot drift apart.
    describe "charge cache gate" do
      let(:charge_cache_key) do
        [
          "charge-usage",
          Subscriptions::ChargeCacheService::CACHE_KEY_VERSION,
          charge.id,
          subscription.id,
          charge.updated_at.iso8601
        ].join("/")
      end

      before { allow(Events::BillingPeriodFilterService).to receive(:for_charges!).and_call_original }

      context "when the usage is not filtered" do
        subject(:usage_service) do
          described_class.new(customer:, subscription:, apply_taxes: false, with_cache: true)
        end

        it "caches the charge and requests the ingestion timestamps" do
          expect { usage_service.call }.to change { Rails.cache.exist?(charge_cache_key) }.from(false).to(true)
          expect(Events::BillingPeriodFilterService).to have_received(:for_charges!)
            .with(hash_including(codes: nil, with_last_seen_at: true))
        end
      end

      context "when the usage is filtered by charge" do
        subject(:usage_service) do
          described_class.new(
            customer:,
            subscription:,
            apply_taxes: false,
            with_cache: true,
            usage_filters: UsageFilters.new(filter_by_charge_id: charge.id)
          )
        end

        it "restricts the lookup to the filtered codes and keeps the timestamps" do
          expect { usage_service.call }.to change { Rails.cache.exist?(charge_cache_key) }.from(false).to(true)
          expect(Events::BillingPeriodFilterService).to have_received(:for_charges!)
            .with(hash_including(codes: [billable_metric.code], with_last_seen_at: true))
        end
      end

      context "when the cache is disabled by the caller" do
        subject(:usage_service) do
          described_class.new(customer:, subscription:, apply_taxes: false, with_cache: false)
        end

        it "skips both the cache and the ingestion timestamps" do
          expect { usage_service.call }.not_to change { Rails.cache.exist?(charge_cache_key) }.from(false)
          expect(Events::BillingPeriodFilterService).to have_received(:for_charges!)
            .with(hash_including(with_last_seen_at: false))
        end
      end

      context "when the usage is filtered by group" do
        subject(:usage_service) do
          described_class.new(
            customer:,
            subscription:,
            apply_taxes: false,
            with_cache: true,
            usage_filters: UsageFilters.new(filter_by_group: {"cloud" => ["aws"]})
          )
        end

        let(:billable_metric) { create(:billable_metric, aggregation_type: "sum_agg", field_name: "value") }

        let(:charge) do
          create(:standard_charge, plan:, billable_metric:, properties: {amount: "10", pricing_group_keys: %w[cloud]})
        end

        let(:events) { [] }

        before do
          create(:event, organization:, subscription:, customer:, code: billable_metric.code,
            timestamp:, properties: {cloud: "aws", value: 10})
        end

        it "skips both the cache and the ingestion timestamps" do
          expect { usage_service.call }.not_to change { Rails.cache.exist?(charge_cache_key) }.from(false)
          expect(Events::BillingPeriodFilterService).to have_received(:for_charges!)
            .with(hash_including(with_last_seen_at: false))
        end
      end

      context "when the full usage is queried outside of the first billing period", :premium do
        subject(:usage_service) do
          described_class.new(
            customer:,
            subscription:,
            apply_taxes: false,
            with_cache: true,
            usage_filters: UsageFilters.new(filter_by_charge_id: charge.id, full_usage: true)
          )
        end

        let(:full_usage_cache_key) do
          Subscriptions::ChargeCacheService.new(subscription:, charge:, full_usage: true).cache_key
        end

        let(:current_usage_cache_key) do
          Subscriptions::ChargeCacheService.new(subscription:, charge:).cache_key
        end

        before { organization.update!(premium_integrations: %w[granular_lifetime_usage]) }

        it "caches the charge under the full usage key and requests the ingestion timestamps" do
          expect { usage_service.call }
            .to change { Rails.cache.exist?(full_usage_cache_key) }.from(false).to(true)

          expect(Rails.cache.exist?(current_usage_cache_key)).to be(false)
          expect(Events::BillingPeriodFilterService).to have_received(:for_charges!)
            .with(hash_including(with_last_seen_at: true))
        end
      end

      # An organization that cannot query full usage never populates either entry.
      context "when the full usage is queried without the granular lifetime usage integration", :premium do
        subject(:usage_service) do
          described_class.new(
            customer:,
            subscription:,
            apply_taxes: false,
            with_cache: true,
            usage_filters: UsageFilters.new(filter_by_charge_id: charge.id, full_usage: true)
          )
        end

        it "refuses the request and caches nothing" do
          result = usage_service.call

          expect(result.error.code).to eq("full_usage_not_allowed")
          expect(Rails.cache.exist?("#{charge_cache_key}/full-usage")).to be(false)
          expect(Rails.cache.exist?(charge_cache_key)).to be(false)
        end
      end

      # skip_grouping and filter_by_presentation change the fees but are absent from the key, so
      # neither may leave an entry another shape would read.
      context "when the full usage is queried with filters the cache key cannot describe", :premium do
        subject(:usage_service) do
          described_class.new(
            customer:,
            subscription:,
            apply_taxes: false,
            with_cache: true,
            usage_filters: UsageFilters.new(filter_by_charge_id: charge.id, full_usage: true, skip_grouping: true)
          )
        end

        let(:full_usage_cache_key) do
          Subscriptions::ChargeCacheService.new(subscription:, charge:, full_usage: true).cache_key
        end

        let(:current_usage_cache_key) do
          Subscriptions::ChargeCacheService.new(subscription:, charge:).cache_key
        end

        # granular_lifetime_usage is on, so the refusal can only come from the filter shape.
        before { organization.update!(premium_integrations: %w[granular_lifetime_usage]) }

        it "skips both the cache and the ingestion timestamps" do
          expect { usage_service.call }.not_to change { Rails.cache.exist?(full_usage_cache_key) }.from(false)

          expect(Rails.cache.exist?(current_usage_cache_key)).to be(false)
          expect(Events::BillingPeriodFilterService).to have_received(:for_charges!)
            .with(hash_including(with_last_seen_at: false))
        end
      end
    end
  end

  describe "with the usage buckets", clickhouse: {clean_before: true} do
    subject(:usage_service) do
      described_class.new(customer:, subscription:, apply_taxes: false, use_usage_buckets: true)
    end

    include_context "with realtime usage availability"

    let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: "count_agg") }
    let(:window_start) { Time.current.beginning_of_month }

    # Serving the buckets requires the organization to read the clickhouse events store, so the
    # fallback has to count clickhouse events rather than the postgres ones the other specs use.
    let(:events) do
      create_list(
        :clickhouse_events_enriched,
        2,
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        code: billable_metric.code,
        timestamp:
      )
    end

    before do
      organization.update!(clickhouse_events_store: true)
      organization.enable_feature_flag!(:realtime_usage)
      create(:tax, :applied_to_billing_entity, organization:, rate: 0)
      charge
      events

      create(
        :clickhouse_usage_bucket,
        organization:, customer:, subscription:, charge:, billable_metric:,
        bucket: window_start,
        units: "5.0",
        events_count: 5,
        aggregation_type: "count_agg"
      )
    end

    it "serves the units of the buckets instead of counting the events" do
      usage = usage_service.call.usage

      expect(usage.fees.first).to have_attributes(units: 5, events_count: 5)
    end

    context "when the bucket read fails" do
      before do
        allow(RealtimeUsage::FetchBucketsService).to receive(:call).and_return(
          RealtimeUsage::FetchBucketsService::Result.new.tap do
            it.service_failure!(code: "usage_buckets_read_failure", message: "clickhouse is unreachable")
          end
        )
      end

      it "counts the events, an unreachable clickhouse making current usage slow rather than broken" do
        expect(usage_service.call.usage.fees.first).to have_attributes(units: 2)
      end

      it "raises under the forced gate, which only the parity comparison opens" do
        expect { RealtimeUsage.with_forced_gate { usage_service.call } }
          .to raise_error(BaseService::FailedResult)
      end
    end

    context "with the provider and the bucket fetch spied on" do
      before do
        allow(Events::Stores::Provider).to receive(:new).and_call_original
        allow(RealtimeUsage::FetchBucketsService).to receive(:call).and_call_original
      end

      it "builds one provider for the whole computation, which reads clickhouse once" do
        usage_service.call

        expect(Events::Stores::Provider).to have_received(:new).once
        expect(RealtimeUsage::FetchBucketsService).to have_received(:call).once
      end
    end

    context "when the organization flag is off" do
      before { organization.disable_feature_flag!(:realtime_usage) }

      it "counts the events" do
        usage = usage_service.call.usage

        expect(usage.fees.first).to have_attributes(units: 2)
      end
    end

    context "when the caller did not ask for the buckets" do
      subject(:usage_service) { described_class.new(customer:, subscription:, apply_taxes: false) }

      it "counts the events, as a caller nobody considered has to keep today's behaviour" do
        usage = usage_service.call.usage

        expect(usage.fees.first).to have_attributes(units: 2)
      end
    end

    context "with a projected read" do
      subject(:usage_service) do
        described_class.new(
          customer:,
          subscription:,
          apply_taxes: false,
          calculate_projected_usage: true,
          use_usage_buckets: true
        )
      end

      before { allow(RealtimeUsage::FetchBucketsService).to receive(:call).and_call_original }

      it "counts the events, which the projection re-aggregates from at presentation time" do
        usage = usage_service.call.usage

        expect(usage.fees.first).to have_attributes(units: 2)
        expect(RealtimeUsage::FetchBucketsService).not_to have_received(:call)
      end
    end

    context "with a lifetime window", :premium do
      subject(:usage_service) do
        described_class.new(
          customer:,
          subscription:,
          apply_taxes: false,
          with_cache: false,
          usage_filters: UsageFilters.new(filter_by_charge_id: charge.id, full_usage: true),
          use_usage_buckets: true
        )
      end

      let(:subscription) { create(:subscription, plan:, customer:, started_at: window_start) }

      before { organization.update!(premium_integrations: %w[granular_lifetime_usage]) }

      it "counts the events, as the window reaches past what the buckets retain" do
        usage = usage_service.call.usage

        expect(usage.fees.first).to have_attributes(units: 2)
      end

      context "when the buckets are reachable" do
        before { allow(RealtimeUsage::FetchBucketsService).to receive(:call).and_call_original }

        it "is refused for the window itself, which the provider rules out before the fetch" do
          usage_service.call

          expect(RealtimeUsage::FetchBucketsService).not_to have_received(:call)
        end
      end
    end

    context "with a delegated charge next to the served one" do
      # unique_count cannot be recomposed from per-bucket distincts, so this charge reads
      # events while the count_agg one next to it is served by the same computation.
      let(:delegated_metric) { create(:unique_count_billable_metric, organization:) }
      let(:delegated_charge) { create(:standard_charge, plan:, billable_metric: delegated_metric, properties: {amount: "1"}) }
      let(:cached_charges) { [] }
      let(:invalidation_timestamps) { [] }

      before do
        delegated_charge

        # A charge with no event in the window is dropped before the cache is consulted, so
        # this one has to have been used for the assertion to say anything.
        create(
          :clickhouse_events_enriched,
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          code: delegated_metric.code,
          timestamp:,
          properties: {"item_id" => "item_1"}
        )

        allow(Subscriptions::ChargeCacheService).to receive(:call) do |**args, &block|
          cached_charges << args[:charge]
          invalidation_timestamps << args[:invalidate_if_older_than]
          block.call
        end
      end

      it "caches the charge it delegated and only that one" do
        usage_service.call

        expect(cached_charges).to eq([delegated_charge])
      end

      it "keeps the ingestion timestamp the delegated charge's cache is invalidated on" do
        usage_service.call

        expect(invalidation_timestamps).to contain_exactly(be_present)
      end
    end

    context "with the events store queries spied on" do
      let(:combination_queries) { [] }
      let(:queried_codes) { combination_queries.flat_map { it[:codes] } }

      before do
        allow(Events::Stores::ClickhouseStore).to receive(:new).and_wrap_original do |build, **args|
          build.call(**args).tap do |store|
            allow(store).to receive(:distinct_codes_and_property_combinations).and_wrap_original do |query, **options|
              combination_queries << options
              query.call(**options)
            end
          end
        end
      end

      it "resolves the billing period filters without reading the events store at all" do
        usage_service.call

        expect(combination_queries).to be_empty
      end

      context "when the bucket read came back empty" do
        before do
          allow(RealtimeUsage::FetchBucketsService).to receive(:call)
            .and_return(RealtimeUsage::FetchBucketsService::Result.new)
        end

        it "keeps the charge in the pre-filter and bills it from the events" do
          usage = usage_service.call.usage

          expect(queried_codes).to eq([billable_metric.code])
          expect(usage.fees.first).to have_attributes(units: 2)
        end
      end

      context "when the organization flag is off" do
        before { organization.disable_feature_flag!(:realtime_usage) }

        it "asks the events store for the plan, as before" do
          usage_service.call

          expect(queried_codes).to eq([billable_metric.code])
        end
      end

      context "with a charge the buckets cannot answer next to the served one" do
        let(:delegated_metric) { create(:unique_count_billable_metric, organization:) }

        before do
          create(:standard_charge, plan:, billable_metric: delegated_metric, properties: {amount: "1"})
        end

        it "asks the events store for the delegated code only" do
          usage_service.call

          expect(queried_codes).to eq([delegated_metric.code])
        end
      end

      context "with a second charge on the code of the served one" do
        # A percentage charge walks the events one by one, so the code it shares with the served
        # charge still has to be resolved from the events store.
        before { create(:percentage_charge, plan:, billable_metric:, properties: {rate: "1"}) }

        it "keeps the shared code in the query" do
          usage_service.call

          expect(queried_codes).to eq([billable_metric.code])
        end
      end

      context "with a presentation breakdown the caller asked none of" do
        subject(:usage_service) do
          described_class.new(
            customer:,
            subscription:,
            apply_taxes: false,
            usage_filters: UsageFilters::WITHOUT_PRESENTATION_FILTER,
            use_usage_buckets: true
          )
        end

        let(:charge) do
          create(
            :standard_charge,
            plan:,
            billable_metric:,
            properties: {amount: "1", presentation_group_keys: [{"value" => "region"}]}
          )
        end

        # How the wallet refresh reads usage: no pricing bucket of the charge reads an event for a
        # breakdown, so the buckets answer the charge whole and the pre-filter must say so too.
        it "serves the charge from the buckets, without an events store read" do
          usage = usage_service.call.usage

          expect(combination_queries).to be_empty
          expect(usage.fees.first).to have_attributes(units: 5, events_count: 5)
        end
      end

      context "when no charge of the plan is eligible" do
        let(:charge) { create(:percentage_charge, plan:, billable_metric:, properties: {rate: "1"}) }

        before { allow(RealtimeUsage::FetchBucketsService).to receive(:call).and_call_original }

        it "reads no bucket, and the events store exactly as before" do
          usage_service.call

          expect(RealtimeUsage::FetchBucketsService).not_to have_received(:call)
          expect(queried_codes).to eq([billable_metric.code])
        end
      end
    end

    context "with the charge computation spied on" do
      before { allow(Fees::ChargeService).to receive(:call!).and_call_original }

      it "hands the served charge the filters the buckets hold usage for" do
        usage_service.call

        expect(Fees::ChargeService).to have_received(:call!).with(hash_including(filtered_aggregations: [nil]))
      end
    end

    context "with charge filters the buckets only partly hold usage for" do
      let(:billable_metric_filter) do
        create(:billable_metric_filter, billable_metric:, key: "region", values: %w[eu us])
      end
      let(:eu_filter) { create(:charge_filter, charge:, properties: {amount: "12.66"}) }
      let(:us_filter) { create(:charge_filter, charge:, properties: {amount: "4"}) }

      let(:eu_fee) { usage_service.call.usage.fees.find { it.charge_filter_id == eu_filter.id } }
      let(:us_fee) { usage_service.call.usage.fees.find { it.charge_filter_id == us_filter.id } }

      before do
        create(:charge_filter_value, charge_filter: eu_filter, billable_metric_filter:, values: %w[eu])
        create(:charge_filter_value, charge_filter: us_filter, billable_metric_filter:, values: %w[us])

        create(
          :clickhouse_usage_bucket,
          organization:, customer:, subscription:, charge:, billable_metric:,
          charge_filter_id: eu_filter.id,
          bucket: window_start,
          units: "3.0",
          events_count: 3,
          aggregation_type: "count_agg"
        )

        # The events store holds usage for the filter the buckets do not, which the pre-filtering
        # must not reach for.
        create(
          :clickhouse_events_enriched,
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          code: billable_metric.code,
          timestamp:,
          properties: {"region" => "us"}
        )
      end

      it "serves the filter the buckets hold, without an events store read" do
        expect(eu_fee).to have_attributes(units: 3, events_count: 3)
      end

      it "zeroes the filter no bucket holds usage for" do
        expect(us_fee).to have_attributes(units: 0, events_count: 0)
      end
    end
  end

  describe "the buckets and the events store agree", clickhouse: {clean_before: true} do
    include_context "with realtime usage availability"

    let(:billable_metric) { create(:sum_billable_metric, organization:) }
    let(:charge) { create(:standard_charge, plan:, billable_metric:, properties: {amount: "2"}) }
    let(:window_start) { Time.current.beginning_of_month }

    let(:event_values) do
      {
        window_start => "5.5",
        window_start + 20.minutes => "4.25",
        window_start + 23.minutes => "1.25",
        window_start + 3.hours => "10.0"
      }
    end

    before do
      organization.update!(clickhouse_events_store: true)
      organization.enable_feature_flag!(:realtime_usage)
      charge

      event_values.each do |at, value|
        create(
          :clickhouse_events_enriched,
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          code: billable_metric.code,
          timestamp: at,
          value:,
          decimal_value: value.to_f
        )
      end

      # The rows the pipeline would have written for those very events, so any difference
      # between the two answers comes from the read path rather than from the fixtures.
      event_values.group_by { |at, _| Time.zone.at(at.to_i - (at.to_i % 15.minutes.to_i)) }.each do |bucket, values|
        create(
          :clickhouse_usage_bucket,
          organization:, customer:, subscription:, charge:, billable_metric:,
          bucket:,
          units: values.sum { |_, value| value.to_d }.to_s,
          events_count: values.size,
          aggregation_type: "sum_agg"
        )
      end
    end

    it "returns the same units, event count and amount either way" do
      served = described_class.new(customer:, subscription:, apply_taxes: false, with_cache: false, use_usage_buckets: true).call.usage
      delegated = described_class.new(customer:, subscription:, apply_taxes: false, with_cache: false).call.usage

      expect(served.fees.first).to have_attributes(
        units: delegated.fees.first.units,
        events_count: delegated.fees.first.events_count,
        amount_cents: delegated.fees.first.amount_cents
      )
    end

    it "sums every bucket of the window, rather than the one the events happen to open" do
      served = described_class.new(customer:, subscription:, apply_taxes: false, with_cache: false, use_usage_buckets: true).call.usage

      expect(served.fees.first).to have_attributes(units: 21, events_count: 4, amount_cents: 4200)
    end
  end

  describe "the buckets and the events store agree on max and latest", clickhouse: {clean_before: true} do
    include_context "with realtime usage availability"

    let(:charge) { create(:standard_charge, plan:, billable_metric:, properties: {amount: "2"}) }
    let(:window_start) { Time.current.beginning_of_month }

    # The largest event is not the last one, and it shares its bucket with a smaller later event,
    # so max and latest disagree both inside a bucket and across the window.
    let(:event_values) do
      {
        window_start => "5.5",
        window_start + 20.minutes => "12.0",
        window_start + 23.minutes => "1.25",
        window_start + 3.hours => "2.0"
      }
    end

    let(:served) do
      described_class.new(customer:, subscription:, apply_taxes: false, with_cache: false, use_usage_buckets: true).call.usage
    end
    let(:delegated) do
      described_class.new(customer:, subscription:, apply_taxes: false, with_cache: false).call.usage
    end

    def bucket_units(values)
      pair = (billable_metric.aggregation_type == "max_agg") ? values.max_by { it.last.to_d } : values.max_by(&:first)
      pair.last
    end

    before do
      organization.update!(clickhouse_events_store: true)
      organization.enable_feature_flag!(:realtime_usage)
      charge

      event_values.each do |at, value|
        create(
          :clickhouse_events_enriched,
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          code: billable_metric.code,
          timestamp: at,
          value:,
          decimal_value: value.to_f
        )
      end

      # The rows the pipeline would have written for those very events, so any difference
      # between the two answers comes from the read path rather than from the fixtures.
      event_values.group_by { |at, _| Time.zone.at(at.to_i - (at.to_i % 15.minutes.to_i)) }.each do |bucket, values|
        create(
          :clickhouse_usage_bucket,
          organization:, customer:, subscription:, charge:, billable_metric:,
          bucket:,
          units: bucket_units(values),
          events_count: values.size,
          aggregation_type: billable_metric.aggregation_type,
          last_event_at: values.map(&:first).max
        )
      end
    end

    context "with a max metric" do
      let(:billable_metric) { create(:max_billable_metric, organization:) }

      it "returns the same units, event count and amount either way" do
        expect(served.fees.first).to have_attributes(
          units: delegated.fees.first.units,
          events_count: delegated.fees.first.events_count,
          amount_cents: delegated.fees.first.amount_cents
        )
      end

      it "serves the largest event of the window, rather than the largest bucket total" do
        expect(served.fees.first).to have_attributes(units: 12, events_count: 4, amount_cents: 2400)
      end
    end

    context "with a latest metric" do
      let(:billable_metric) { create(:latest_billable_metric, organization:) }

      it "returns the same units, event count and amount either way" do
        expect(served.fees.first).to have_attributes(
          units: delegated.fees.first.units,
          events_count: delegated.fees.first.events_count,
          amount_cents: delegated.fees.first.amount_cents
        )
      end

      it "serves the last event of the window, counting every event of it alongside" do
        expect(served.fees.first).to have_attributes(units: 2, events_count: 4, amount_cents: 400)
      end
    end
  end

  describe "the buckets and the events store agree when the caller skips grouping", clickhouse: {clean_before: true} do
    include_context "with realtime usage availability"

    let(:billable_metric) { create(:latest_billable_metric, organization:) }
    let(:charge) do
      create(:standard_charge, plan:, billable_metric:, properties: {amount: "2", pricing_group_keys: ["region"]})
    end
    let(:window_start) { Time.current.beginning_of_month }

    # Both groups close on the same bucket, so only the event time says which one holds the value
    # the events store would return for the ungrouped charge.
    let(:group_events) do
      [
        {at: window_start + 10.minutes, value: "7.0", region: "eu"},
        {at: window_start + 12.minutes, value: "3.0", region: "us"}
      ]
    end

    let(:served) do
      described_class.new(
        customer:, subscription:, apply_taxes: false, with_cache: false,
        usage_filters: UsageFilters.new(skip_grouping: true), use_usage_buckets: true
      ).call.usage
    end
    let(:delegated) do
      described_class.new(
        customer:, subscription:, apply_taxes: false, with_cache: false,
        usage_filters: UsageFilters.new(skip_grouping: true)
      ).call.usage
    end

    before do
      organization.update!(clickhouse_events_store: true)
      organization.enable_feature_flag!(:realtime_usage)
      charge

      group_events.each do |group_event|
        create(
          :clickhouse_events_enriched,
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          code: billable_metric.code,
          timestamp: group_event[:at],
          properties: {"region" => group_event[:region]},
          value: group_event[:value],
          decimal_value: group_event[:value].to_f
        )

        create(
          :clickhouse_usage_bucket,
          organization:, customer:, subscription:, charge:, billable_metric:,
          bucket: window_start,
          grouped_by: {"region" => group_event[:region]}.to_json,
          units: group_event[:value],
          events_count: 1,
          aggregation_type: "latest_agg",
          last_event_at: group_event[:at]
        )
      end
    end

    it "folds the groups onto the last event, rather than onto whichever row comes first" do
      expect(served.fees.first).to have_attributes(
        units: delegated.fees.first.units,
        events_count: delegated.fees.first.events_count
      )
      expect(served.fees.first).to have_attributes(units: 3, events_count: 2)
    end
  end
end
