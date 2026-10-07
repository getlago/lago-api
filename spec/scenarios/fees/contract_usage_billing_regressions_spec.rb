# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Contract usage billing QA regressions" do
  let(:organization) { create(:organization, feature_flags: ["product_catalog"], webhook_url: nil) }
  let(:customer) { create(:customer, organization:, currency: "USD", timezone: "UTC") }
  let(:started_at) { Time.zone.parse("2026-10-06 00:00:00") }
  let(:boundary) { started_at + 1.month }
  let(:contract) do
    create(:contract, organization:, customer:, started_at:, billing_time: :anniversary,
      billing_entity: customer.billing_entity)
  end
  let(:aggregation_type) { :sum_agg }
  let(:recurring) { true }
  let(:field_name) { "units" }
  let(:billable_metric) do
    create(:billable_metric, organization:, aggregation_type:, recurring:, field_name:,
      weighted_interval: (aggregation_type == :weighted_sum_agg) ? :seconds : nil)
  end
  let(:product) { create(:product, organization:, billable_metric:) }
  let(:timing) { :advance }
  let(:proration) { false }
  let(:display) { true }
  let(:regroup) { nil }
  let(:product_filter) { nil }
  let(:rate_card) do
    create(:rate_card, organization:, product:, product_filter:, currency: "USD", billing_timing: timing,
      proration:, display_on_invoice: display, regroup_paid_fees: regroup)
  end
  let(:rate_model) { :standard }
  let(:rate_properties) { {"amount" => "1"} }
  let(:billing_interval_unit) { :month }
  let(:rate) do
    RateCardRates::CreateService.call!(rate_card:, params: {
      code: "qa-rate", effective_from: started_at, rate_model:, rate_properties:,
      billing_interval_unit:, billing_interval_count: 1
    }).rate_card_rate
  end
  let(:card) do
    create(:contract_rate_card, organization:, contract:, rate_card:,
      effective_date: started_at.to_date, billing_anchor_date: started_at.to_date,
      next_billing_at: (timing == :advance) ? started_at : boundary)
  end

  around do |example|
    travel_to(started_at + 12.hours) { example.run }
  end

  before do
    rate
    card
  end

  describe "BIL-765 and BIL-764 advance event invoices" do
    subject(:event_fees) do
      inputs.each_with_index do |input, index|
        event_at = input.fetch(:at, started_at + (index + 1).hours)
        travel_to(input.fetch(:received_at, event_at))
        create_event({external_contract_id: contract.external_id, code: billable_metric.code,
          timestamp: event_at.to_i, properties: input.fetch(:properties, {}).merge(field_name => input.fetch(:value))}, perform_jobs: false)
        perform_all_enqueued_jobs(except: [BillingSegments::ScheduleJob, BillingSegments::ProcessJob])
      end
      Fee.where(contract:, fee_type: :product).order(:created_at).to_a
    end

    let(:inputs) { [3, 7, -3, 4].map { |value| {value: value.to_s} } }
    let(:invoices) { event_fees.map(&:invoice).uniq }

    context "when the rebound stays below the billed maximum" do
      let(:inputs) { [3, 7, -3, 2, 2].map { |value| {value: value.to_s} } }

      it "charges nothing until usage exceeds ten" do
        expect(event_fees.map(&:amount_cents)).to eq([300, 700, 0, 0, 100])
      end
    end

    context "when checking usage after a decrease" do
      let(:inputs) { [3, 7, -3].map { |value| {value: value.to_s} } }

      it "reports current usage separately from the billed maximum" do
        event_fees
        event = Event.where(organization:, external_subscription_id: contract.external_id).order(:timestamp).last
        selection = Events::PayInAdvanceMeteredItemsResolver.call!(event:).selections.sole
        item = selection.metered_item
        usage = BillableMetrics::AggregationFactory.new_instance(
          metered_item: item, billing_context: selection.billing_context,
          boundaries: item.aggregation_boundaries, current_usage: true
        ).aggregate(options: {is_current_usage: true, is_pay_in_advance: true})

        expect(usage).to have_attributes(current_usage_units: 7, aggregation: 10)
      end
    end

    context "when usage is grouped" do
      let(:rate_properties) { {"amount" => "1", "pricing_group_keys" => ["region"]} }
      let(:inputs) do
        [[3, "eu"], [7, "eu"], [-3, "eu"], [4, "us"], [4, "eu"]].map do |value, region|
          {value: value.to_s, properties: {"region" => region}}
        end
      end

      it "keeps the current usage and maximum separate for each group" do
        expect(event_fees.map(&:amount_cents)).to eq([300, 700, 0, 400, 100])
      end
    end

    context "when another contract card prices the same metric" do
      let(:other_product) { create(:product, organization:, billable_metric:) }
      let(:other_rate_card) { create(:rate_card, organization:, product: other_product, currency: "USD", billing_timing: timing) }
      let(:other_rate) do
        RateCardRates::CreateService.call!(rate_card: other_rate_card, params: {
          code: "other-rate", effective_from: started_at, rate_model:, rate_properties:,
          billing_interval_unit: :month, billing_interval_count: 1
        }).rate_card_rate
      end
      let!(:other_card) do
        create(:contract_rate_card, organization:, contract:, rate_card: other_rate_card,
          effective_date: started_at.to_date, billing_anchor_date: started_at.to_date, next_billing_at: started_at)
      end

      before { other_rate }

      it "bills each attachment independently" do
        fees_by_card = event_fees.group_by(&:contract_rate_card_id).transform_values { |fees| fees.map(&:amount_cents) }

        expect(fees_by_card).to eq(card.id => [300, 700, 0, 100], other_card.id => [300, 700, 0, 100])
      end
    end

    context "with a product filter" do
      let(:product_filter) { create(:product_filter, organization:, product:) }
      let(:metric_filter) { create(:billable_metric_filter, billable_metric:, key: "region", values: %w[eu us]) }
      let(:inputs) do
        [[3, "eu"], [100, "us"], [7, "eu"], [-3, "eu"], [4, "eu"]].map do |value, region|
          {value: value.to_s, properties: {"region" => region}}
        end
      end

      before do
        create(:product_filter_value, organization:, product_filter:, billable_metric_filter: metric_filter, value: "eu")
      end

      it "keeps unmatched events out of both pricing and persisted state" do
        expect(event_fees.map(&:amount_cents)).to eq([300, 700, 0, 100])
        expect(CachedAggregation.where(contract:, product:).order(:created_at).pluck(:current_aggregation))
          .to eq([3, 10, 7, 11])
      end
    end

    it "O10 bills only the newly reached unit" do
      event_fees
      expect(CachedAggregation.where(contract:, product:).order(:created_at).pluck(:current_aggregation, :max_aggregation))
        .to eq([[3, 3], [10, 10], [7, 10], [11, 11]])
      expect(event_fees.map(&:amount_cents)).to eq([300, 700, 0, 100])
      expect(invoices.map(&:status)).to eq(["finalized"] * 4)
      expect(invoices.sum(&:total_amount_cents)).to eq(1100)
    end

    context "with graduated pricing G10" do
      let(:rate_model) { :graduated }
      let(:rate_properties) do
        {"graduated_ranges" => [
          {"to_value" => "10", "per_unit_amount" => "1", "flat_amount" => "0"},
          {"to_value" => nil, "per_unit_amount" => "0.5", "flat_amount" => "0"}
        ]}
      end

      it "bills only unit eleven" do
        expect(event_fees.map(&:amount_cents)).to eq([300, 700, 0, 50])
        expect(invoices.map(&:status)).to eq(["finalized"] * 4)
        expect(invoices.sum(&:total_amount_cents)).to eq(1050)
      end
    end

    context "with percentage pricing M10" do
      let(:inputs) { [300, 700, -300, 400].map { |value| {value: value.to_s} } }
      let(:rate_model) { :percentage }
      let(:rate_properties) { {"rate" => "2.5", "fixed_amount" => "0.30"} }

      it "bills only the newly reached hundred units plus the event fee" do
        expect(event_fees.map(&:amount_cents)).to eq([780, 1780, 0, 280])
        expect(event_fees.third.amount_details).to include("fixed_fee_total_amount" => "0.0", "paid_events" => "0.0")
        expect(invoices.map(&:status)).to eq(["finalized"] * 4)
        expect(invoices.sum(&:total_amount_cents)).to eq(2840)
      end
    end

    context "with graduated percentage pricing I10" do
      let(:inputs) { [300, 700, -300, 400].map { |value| {value: value.to_s} } }
      let(:rate_model) { :graduated_percentage }
      let(:rate_properties) do
        {"graduated_percentage_ranges" => [
          {"to_value" => "1000", "rate" => "2", "flat_amount" => "0"},
          {"to_value" => nil, "rate" => "1", "flat_amount" => "5"}
        ]}
      end

      it "bills only the new tier exposure and flat fee" do
        expect(event_fees.map(&:amount_cents)).to eq([600, 1400, 0, 600])
        expect(invoices.map(&:status)).to eq(["finalized"] * 4)
        expect(invoices.sum(&:total_amount_cents)).to eq(2600)
      end
    end

    context "with prorated standard pricing O11" do
      let(:proration) { true }
      let(:rate_properties) { {"amount" => "10"} }
      let(:inputs) do
        [[0, 3], [1, 7], [10, -3], [14, 4]].map do |days, value|
          {at: started_at + days.days + 1.hour, value: value.to_s}
        end
      end

      it "prorates the one newly reached unit" do
        expect(event_fees.map(&:amount_cents)).to eq([3000, 6774, 0, 548])
        expect(invoices.map(&:status)).to eq(["finalized"] * 4)
        expect(invoices.sum(&:total_amount_cents)).to eq(10_322)
      end
    end

    context "with nonrecurring unique package pricing K4" do
      let(:aggregation_type) { :unique_count_agg }
      let(:recurring) { false }
      let(:field_name) { "user_id" }
      let(:rate_model) { :package }
      let(:rate_properties) { {"amount" => "5", "package_size" => 2, "free_units" => 0} }
      let(:inputs) { %w[A A B].map { |value| {value:} } }

      it "bills one package for A, A, B" do
        expect(event_fees.map(&:amount_cents)).to eq([500, 0, 0])
      end

      context "with ClickHouse-backed event aggregation", clickhouse: true do
        subject(:event_fees) do
          Events::Stores::StoreFactory.with_override(store_class: Events::Stores::ClickhouseStore, deduplicate: false) do
            inputs.each_with_index do |input, index|
              travel_to(started_at + (index + 1).hours)
              attributes = {
                organization_id: organization.id, external_subscription_id: contract.external_id,
                code: billable_metric.code, transaction_id: "qa-#{index}", timestamp: Time.current,
                properties: {field_name => input.fetch(:value)}
              }
              Clickhouse::EventsEnriched.create!(**attributes, value: input.fetch(:value), enriched_at: Time.current)
              Events::PayInAdvanceService.call!(event: Events::Common.new(**attributes))
              perform_all_enqueued_jobs(except: [BillingSegments::ScheduleJob, BillingSegments::ProcessJob])
            end
          end
          Fee.where(contract:, fee_type: :product).order(:created_at).to_a
        end

        let(:organization) do
          create(:organization, feature_flags: ["product_catalog"], webhook_url: nil, clickhouse_events_store: true)
        end

        it "bills one package for A, A, B" do
          expect(event_fees.map(&:amount_cents)).to eq([500, 0, 0])
        end
      end
    end
  end

  describe "BIL-756 BM9 recurring weighted SUM" do
    subject(:billing_result) { Contracts::BillService.call!(contracts: [contract], timestamp: boundary) }

    let(:started_at) { Time.zone.parse("2026-10-02 00:00:00") }
    let(:timing) { :arrears }
    let(:aggregation_type) { :weighted_sum_agg }
    let(:field_name) { "gb" }
    let(:event) do
      create(:event, organization:, customer:, external_subscription_id: contract.external_id,
        code: billable_metric.code, timestamp: started_at, properties: {"gb" => "10"})
    end

    before { event }

    it "bills ten weighted units without a subscription context" do
      expect(billing_result.invoices.sole.fees.sole).to have_attributes(units: 10, amount_cents: 1000)
    end

    context "when manually billing the monthly contract" do
      subject(:manual_billing) do
        post_with_token(organization, "/api/v2/contracts/#{contract.external_id}/bill?end_on=#{end_on}")
      end

      let(:end_on) { "2026-11-02" }

      it "returns the finalized first-period invoice and fee" do
        manual_billing

        expect(response).to have_http_status(:success)
        invoice = Invoice.where(customer:).sole
        expect(json[:invoices].sole).to include(lago_id: invoice.id, status: "finalized", total_amount_cents: 1000)
        expect(invoice.fees.sole).to have_attributes(units: 10, amount_cents: 1000)
      end

      context "when billing through the second period" do
        let(:end_on) { "2026-12-02" }

        it "returns finalized invoices for both periods" do
          manual_billing

          expect(response).to have_http_status(:success)
          expect(json[:invoices].map { |invoice| [invoice[:status], invoice[:total_amount_cents]] })
            .to eq([["finalized", 1000]] * 2)
          expect(Invoice.where(customer:).order(:created_at).flat_map(&:fees).map { |fee| [fee.units, fee.amount_cents] })
            .to eq([[10, 1000]] * 2)
        end
      end
    end

    it "carries ten units into an eventless second period" do
      billing_result
      second_period = Contracts::BillService.call!(contracts: [contract], timestamp: boundary + 1.month)

      expect(second_period.invoices.sole.fees.sole).to have_attributes(units: 10, amount_cents: 1000)
    end

    context "when an effective-date change replaces the contract rate card" do
      subject(:replacement_result) do
        Fees::ChargeService.call!(
          invoice:, metered_item: replacement_item, billing_context: Billing::Context.from(contract:),
          options: Fees::ChargeService::Options.new(context: :finalize)
        )
      end

      let(:event) { nil }
      let(:invoice) { create(:invoice, organization:, customer:, currency: "USD", status: :generating) }
      let(:replacement_rate_card) { create(:rate_card, organization:, product:, currency: "USD", billing_timing: timing) }
      let(:replacement_rate) do
        create(:rate_card_rate, organization:, rate_card: replacement_rate_card, rate_properties: {"amount" => "2"})
      end
      let(:replacement_card) do
        create(:contract_rate_card, organization:, contract:, rate_card: replacement_rate_card,
          effective_date: boundary.to_date, billing_anchor_date: started_at.to_date)
      end
      let(:replacement_segment) do
        create(:billing_segment, organization:, customer:, contract:, contract_rate_card: replacement_card,
          rate_card_rate: replacement_rate, rate_override: nil, currency: "USD", rate_properties: {"amount" => "2"},
          started_at: boundary, ended_at: BillingSegment.inclusive_end(boundary + 1.month),
          cycle_started_at: boundary, billing_at: boundary + 1.month)
      end
      let(:replacement_item) { Fees::ChargeService::MeteredItem.from_billing_segment(billing_segment: replacement_segment) }
      let(:closing_balance) do
        create(:cached_aggregation, organization:, charge: nil, contract: card.contract, product: card.product,
          external_subscription_id: contract.external_id, current_aggregation: 10,
          timestamp: BillingSegment.inclusive_end(boundary))
      end

      before { closing_balance }

      it "carries the cached units into the replacement price without replaying events" do
        expect(replacement_result.fees.sole).to have_attributes(
          contract_rate_card: replacement_card, units: 10, amount_cents: 2000
        )
        expect(replacement_result.cached_aggregations.sole).to have_attributes(contract:, product:, current_aggregation: 10)
      end

      context "with a balance for another contract" do
        let(:other_contract) { create(:contract, organization:, customer:) }
        let(:closing_balance) do
          create(:cached_aggregation, organization:, charge: nil, contract: other_contract, product:,
            external_subscription_id: contract.external_id, current_aggregation: 10,
            timestamp: BillingSegment.inclusive_end(boundary))
        end

        it "keeps the replacement contract's usage isolated" do
          expect(replacement_result.fees).to be_empty
        end
      end
    end

    context "when several periods are billed together" do
      subject(:billing_result) { Contracts::BillService.call!(contracts: [contract], timestamp: boundary + 2.months) }

      it "carries the opening balance through each eventless period" do
        expect(billing_result.invoices.flat_map(&:fees).map { |fee| [fee.units, fee.amount_cents] })
          .to eq([[10, 1000], [10, 1000], [10, 1000]])
      end

      context "with grouped usage" do
        let(:rate_properties) { {"amount" => "1", "pricing_group_keys" => ["region"]} }
        let(:event) do
          create(:event, organization:, customer:, external_subscription_id: contract.external_id,
            code: billable_metric.code, timestamp: started_at, properties: {"gb" => "10", "region" => "eu"})
        end

        it "uses only the latest closing balance for each group" do
          expect(billing_result.invoices.flat_map(&:fees).map { |fee| [fee.units, fee.amount_cents, fee.grouped_by] })
            .to eq([[10, 1000, {"region" => "eu"}]] * 3)
        end
      end
    end

    context "when billing runs naturally on a three-day cadence" do
      subject(:natural_invoice) do
        Clock::CreateBillingSegmentsJob.perform_now
        Clock::ProcessBillingSegmentsJob.perform_now
        perform_all_enqueued_jobs(only: [BillingSegments::ScheduleJob, BillingSegments::ProcessJob])
        Invoice.where(customer:).sole
      end

      let(:boundary) { started_at + 3.days }
      let(:rate) do
        RateCardRates::CreateService.call!(rate_card:, params: {
          code: "qa-rate", effective_from: started_at, rate_model:, rate_properties:,
          billing_interval_unit: :day, billing_interval_count: 3
        }).rate_card_rate
      end

      before { travel_to(boundary + 14.hours + 58.minutes + 14.seconds) }

      it "creates a finalized first-period invoice visible after the cursor advances" do
        expect(natural_invoice).to have_attributes(status: "finalized", total_amount_cents: 1000)
        expect(natural_invoice.fees.sole).to have_attributes(units: 10, amount_cents: 1000)
        expect(contract.reload).to be_active
        expect(card.reload.next_billing_at).to eq(boundary + 3.days)

        get_with_token(organization, "/api/v2/invoices?external_customer_id=#{customer.external_id}")
        expect(response).to have_http_status(:success)
        expect(json[:invoices].map { |invoice| invoice[:lago_id] }).to eq([natural_invoice.id])

        get_with_token(organization, "/api/v2/fees?external_customer_id=#{customer.external_id}")
        expect(response).to have_http_status(:success)
        expect(json[:fees].map { |fee| fee[:lago_id] }).to eq([natural_invoice.fees.sole.id])
      end
    end
  end

  describe "BIL-768 TM4 paid fee reconciliation" do
    subject(:natural_invoices) do
      [boundary, observed_at].each do |timestamp|
        travel_to(timestamp)
        Clock::CreateBillingSegmentsJob.perform_now
        Clock::ProcessBillingSegmentsJob.perform_now
        perform_all_enqueued_jobs(only: billing_jobs)
      end
      Invoice.where(customer:).to_a
    end

    let(:recurring) { false }
    let(:display) { false }
    let(:regroup) { :invoice }
    let(:billing_interval_unit) { :day }
    let(:boundary) { started_at + 1.day }
    let(:observed_at) { boundary + 8.hours + 11.minutes }
    let(:billing_jobs) { [BillingSegments::ScheduleJob, BillingSegments::ProcessJob] }
    let(:fees) { Fee.where(contract:, fee_type: :product).order(:created_at).to_a }

    before do
      travel_to(started_at)
      Clock::CreateBillingSegmentsJob.perform_now
      perform_all_enqueued_jobs(only: billing_jobs)

      [3, 7, 1, 1, 1].each_with_index do |units, index|
        travel_to(started_at + (index + 1).hours)
        create_event({external_contract_id: contract.external_id, code: billable_metric.code,
          timestamp: Time.current.to_i, properties: {field_name => units}}, perform_jobs: false)
        perform_all_enqueued_jobs(except: billing_jobs)
      end

      fees.first(3).each { |fee| Fees::UpdateService.call!(fee:, params: {payment_status: "succeeded"}) }
    end

    it "creates standalone event fees before the natural close" do
      expect(fees.map(&:amount_cents)).to eq([300, 700, 100, 100, 100])
      expect(fees.map(&:payment_status)).to eq(%w[succeeded succeeded succeeded pending pending])
      expect(fees.map(&:invoice_id)).to eq([nil] * 5)
      expect(Invoice.where(customer:)).to be_empty
      expect(card.reload.next_billing_at).to eq(boundary)
    end

    it "regroups only paid fees at daily close and has one invoice at 08:11 UTC" do
      invoice = natural_invoices.sole

      expect(invoice).to have_attributes(
        total_amount_cents: 1100, payment_status: "succeeded", status: "finalized", created_at: boundary
      )
      expect(invoice.fees.pluck(:id)).to match_array(fees.first(3).map(&:id))
      expect(fees.map { |fee| fee.reload.invoice_id }).to eq([invoice.id, invoice.id, invoice.id, nil, nil])
      expect(fees.map(&:amount_cents)).to eq([300, 700, 100, 100, 100])
      expect(fees.map(&:payment_status)).to eq(%w[succeeded succeeded succeeded pending pending])
      expect(contract.reload).to be_active
      expect(card.reload.next_billing_at).to eq(boundary + 1.day)

      %w[v1 v2].each do |version|
        get_with_token(organization, "/api/#{version}/customers/#{customer.external_id}/invoices")
        expect(response).to have_http_status(:success)
        expect(json[:invoices].map { |item| item[:lago_id] }).to eq([invoice.id])
      end
    end

    context "without paid-fee regrouping" do
      let(:regroup) { nil }

      it "advances the daily billing date without invoicing any fees" do
        expect(natural_invoices).to eq([])
        expect(card.reload.next_billing_at).to eq(boundary + 1.day)
        expect(contract.reload).to be_active
        expect(fees.map { |fee| fee.reload.invoice_id }).to eq([nil] * 5)
        expect(fees.map(&:amount_cents)).to eq([300, 700, 100, 100, 100])
        expect(fees.map(&:payment_status)).to eq(%w[succeeded succeeded succeeded pending pending])

        %w[v1 v2].each do |version|
          get_with_token(organization, "/api/#{version}/customers/#{customer.external_id}/invoices")
          expect(response).to have_http_status(:success)
          expect(json[:invoices]).to eq([])
        end
      end
    end

    context "when manually billing a separate monthly fixture early" do
      subject(:manual_billing) { post_with_token(organization, bill_path) }

      let(:billing_interval_unit) { :month }
      let(:boundary) { started_at + 1.month }
      let(:bill_path) { "/api/v2/contracts/#{contract.external_id}/bill?end_on=#{boundary.to_date.iso8601}" }

      it "supports the future November 6 cutoff and returns the paid invoice" do
        manual_billing

        expect(Time.current.to_date).to eq(started_at.to_date)
        expect(response).to have_http_status(:success)
        expect(json[:invoices].sole).to include(total_amount_cents: 1100, payment_status: "succeeded", status: "finalized")
        invoice = Invoice.where(customer:).sole
        expect(invoice).to have_attributes(total_amount_cents: 1100, payment_status: "succeeded", status: "finalized")
        expect(json[:invoices].sole[:lago_id]).to eq(invoice.id)
        expect(invoice.fees.pluck(:id)).to match_array(fees.first(3).map(&:id))
        expect(fees.map { |fee| fee.reload.invoice_id }).to eq([invoice.id, invoice.id, invoice.id, nil, nil])
      end

      it "does not invoice the paid fees again on retry" do
        manual_billing

        expect do
          post_with_token(organization, bill_path)
        end.not_to change(Invoice, :count)
        expect(response).to have_http_status(:success)
        expect(json[:invoices]).to eq([])
      end
    end
  end
end
