# frozen_string_literal: true

require "rails_helper"

RSpec.describe CopyToProduction::CopyService do
  subject(:result) { described_class.call(organization:, user:, item_type:, id:) }

  let(:production) { create(:organization, :self_serve) }
  let(:sandbox) { create(:organization, :sandbox, production_organization: production, self_serve: true) }
  let(:organization) { sandbox }
  let(:user) { create(:user) }
  let(:production_roles) { %i[admin] }
  let(:production_membership) { create(:membership, user:, organization: production, roles: production_roles) }
  let(:item_type) { "billable_metric" }
  let(:id) { metric.id }

  let(:metric) do
    create(
      :billable_metric,
      organization: sandbox,
      code: "api_calls",
      name: "API calls",
      description: "Calls to the public API",
      aggregation_type: "weighted_sum_agg",
      weighted_interval: "seconds",
      recurring: true,
      field_name: "amount",
      expression: "round(event.properties.amount * 2)",
      rounding_function: "round",
      rounding_precision: 2
    )
  end

  before do
    production_membership
    create(:membership, user:, organization: sandbox, roles: %i[admin])
    create(:billable_metric_filter, billable_metric: metric, key: "region", values: %w[eu us])
    create(:billable_metric_filter, billable_metric: metric, key: "tier", values: %w[free paid])
  end

  it "copies the billable metric and its filters to production" do
    expect { result }.to change { production.billable_metrics.count }.by(1)

    copy = production.billable_metrics.find_by(code: "api_calls")
    expect(result).to be_success
    expect(result.item).to eq(CopyToProduction::CopyService::Entry.new(item_type: "billable_metric", record: copy))
    expect(copy).to have_attributes(
      name: "API calls",
      description: "Calls to the public API",
      aggregation_type: "weighted_sum_agg",
      weighted_interval: "seconds",
      recurring: true,
      field_name: "amount",
      expression: "round(event.properties.amount * 2)",
      rounding_function: "round",
      rounding_precision: 2
    )
    expect(copy.filters.map { [it.key, it.values, it.organization_id] })
      .to eq([["region", %w[eu us], production.id], ["tier", %w[free paid], production.id]])
    expect(sandbox.billable_metrics.find_by(code: "api_calls").filters.count).to eq(2)
  end

  context "with a membership in the context" do
    around { |example| CurrentContext.set(membership: "membership/sandbox") { example.run } }

    it "restores it" do
      result

      expect(CurrentContext.membership).to eq("membership/sandbox")
    end
  end

  context "with activity logs", :capture_kafka_messages do
    let(:activity_log_env) do
      {
        "LAGO_CLICKHOUSE_ENABLED" => "true",
        "LAGO_KAFKA_BOOTSTRAP_SERVERS" => "kafka",
        "LAGO_KAFKA_ACTIVITY_LOGS_TOPIC" => "activity_logs"
      }
    end

    around { |example| CurrentContext.set(source: "graphql") { example.run } }

    before { stub_const("ENV", ENV.to_h.merge(activity_log_env)) }

    it "logs the creation and the copy in production, attributed to the user" do
      result

      logs = kafka_messages.map { JSON.parse(it[:payload]) }
      expect(logs.map { it.slice("activity_type", "organization_id", "resource_id", "user_id") }).to match_array(
        %w[billable_metric.created billable_metric.copied_to_production].map do |activity_type|
          {
            "activity_type" => activity_type,
            "organization_id" => production.id,
            "resource_id" => result.item.record.id,
            "user_id" => user.id
          }
        end
      )
    end
  end

  context "when production has a metric with the same code" do
    before { create(:billable_metric, organization: production, code: "api_calls") }

    it "copies nothing" do
      expect { result }.not_to change(BillableMetric, :count)

      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::ValidationFailure)
      expect(result.error.messages).to eq(code: ["value_already_exist"])
    end
  end

  context "when the organization is a production" do
    let(:organization) { production }

    it "refuses the copy" do
      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::ForbiddenFailure)
      expect(result.error.code).to eq("copy_to_production_sandbox_only")
    end
  end

  context "when the sandbox has no such metric" do
    let(:id) { create(:billable_metric, organization: production).id }

    it "answers not found" do
      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::NotFoundFailure)
      expect(result.error.message).to eq("billable_metric_not_found")
    end
  end

  context "when the user is not an admin of production" do
    let(:production_roles) { %i[finance] }

    it "refuses the copy" do
      expect { result }.not_to change(BillableMetric, :count)

      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::ForbiddenFailure)
      expect(result.error.code).to eq("copy_to_production_admin_only")
    end
  end

  context "when the user is not a member of production" do
    let(:production_membership) { nil }

    it "refuses the copy" do
      expect(result).to be_failure
      expect(result.error.code).to eq("copy_to_production_admin_only")
    end
  end

  context "when production waits for a payment method" do
    include_context "with self-serve enabled"

    before { production.update!(activation_status: "pending_payment_method") }

    it "refuses the copy" do
      expect { result }.not_to change(BillableMetric, :count)

      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::ForbiddenFailure)
      expect(result.error.code).to eq("organization_inactive")
    end
  end

  context "when a create service refuses after the metric is created", :capture_kafka_messages do
    before do
      stub_const("ENV", ENV.to_h.merge("LAGO_CLICKHOUSE_ENABLED" => "true", "LAGO_KAFKA_BOOTSTRAP_SERVERS" => "kafka",
        "LAGO_KAFKA_ACTIVITY_LOGS_TOPIC" => "activity_logs"))
      allow(BillableMetricFilters::CreateOrUpdateBatchService).to receive(:call).and_wrap_original do |original, **args|
        original.call(**args)
        BaseService::Result.new.service_failure!(code: "filters_failed", message: "Filters failed")
      end
    end

    it "answers its error and leaves production unchanged" do
      expect { result }.not_to change(BillableMetric.with_discarded, :count)

      expect(result).to be_failure
      expect(result.error.code).to eq("filters_failed")
      expect(BillableMetricFilter.with_discarded.where(organization: production)).to be_empty
      expect(SendWebhookJob).not_to have_been_enqueued
      expect(kafka_messages).to be_empty
    end
  end

  context "with a feature" do
    let(:item_type) { "feature" }
    let(:id) { feature.id }
    let(:feature) { create(:feature, organization: sandbox, code: "seats", name: "Seats", description: "Seats per workspace") }

    before do
      create(:privilege, feature:, code: "max", name: "Maximum", value_type: "integer", created_at: 2.days.ago)
      create(:privilege, feature:, code: "tier", value_type: "select", config: {select_options: %w[free pro]}, created_at: 1.day.ago)
      create(:privilege, feature:, code: "removed").discard!
    end

    it "copies the feature and its kept privileges to production" do
      expect { result }.to change { production.features.count }.by(1)

      copy = production.features.find_by(code: "seats")
      expect(result).to be_success
      expect(result.item).to eq(CopyToProduction::CopyService::Entry.new(item_type: "feature", record: copy))
      expect(copy).to have_attributes(name: "Seats", description: "Seats per workspace")
      expect(copy.privileges.order(:created_at, :id).map { [it.code, it.name, it.value_type, it.config, it.organization_id] }).to eq(
        [
          ["max", "Maximum", "integer", {}, production.id],
          ["tier", nil, "select", {"select_options" => %w[free pro]}, production.id]
        ]
      )
    end
  end

  context "with a fixed amount coupon on every metric" do
    let(:item_type) { "coupon" }
    let(:id) { coupon.id }
    let(:coupon) do
      create(
        :coupon,
        organization: sandbox,
        code: "launch",
        coupon_type: "fixed_amount",
        amount_cents: 1000,
        amount_currency: "EUR",
        percentage_rate: nil,
        frequency: "once",
        expiration: "no_expiration",
        limited_billable_metrics: false
      )
    end

    it "copies its amount and applies it to every metric" do
      expect { result }.not_to change { production.billable_metrics.count }

      copy = production.coupons.find_by(code: "launch")
      expect(result).to be_success
      expect(copy).to have_attributes(
        coupon_type: "fixed_amount",
        amount_cents: 1000,
        amount_currency: "EUR",
        percentage_rate: nil,
        frequency: "once",
        expiration: "no_expiration",
        limited_billable_metrics: false,
        limited_plans: false
      )
      expect(copy.coupon_targets).to be_empty
    end
  end

  context "with a coupon" do
    let(:item_type) { "coupon" }
    let(:id) { coupon.id }
    let(:coupon) do
      create(
        :coupon,
        organization: sandbox,
        code: "welcome",
        name: "Welcome",
        description: "First months off",
        coupon_type: "percentage",
        percentage_rate: 12.5,
        amount_cents: nil,
        amount_currency: nil,
        frequency: "recurring",
        frequency_duration: 3,
        expiration: "time_limit",
        expiration_at: 1.month.from_now.beginning_of_day,
        reusable: false,
        limited_billable_metrics: true
      )
    end

    let(:live_metric) { create(:billable_metric, organization: production, code: "seats") }
    let(:reused_metric_source) { create(:billable_metric, organization: sandbox, code: "seats") }
    let(:copied_metric_source) { create(:billable_metric, organization: sandbox, code: "storage") }

    before do
      create(:coupon_billable_metric, coupon:, billable_metric: reused_metric_source)
      create(:coupon_billable_metric, coupon:, billable_metric: copied_metric_source)
      live_metric
    end

    it "copies the coupon with its metric targets remapped to production" do
      expect { result }.to change { production.coupons.count }.by(1)
        .and change { production.billable_metrics.count }.by(1)

      copy = production.coupons.find_by(code: "welcome")
      copied_metric = production.billable_metrics.find_by(code: "storage")
      expect(result).to be_success
      expect(result.item).to eq(CopyToProduction::CopyService::Entry.new(item_type: "coupon", record: copy))
      expect(copy).to have_attributes(
        name: "Welcome",
        description: "First months off",
        coupon_type: "percentage",
        percentage_rate: 12.5,
        amount_cents: nil,
        frequency: "recurring",
        frequency_duration: 3,
        expiration: "time_limit",
        expiration_at: coupon.expiration_at,
        reusable: false,
        status: "active",
        limited_billable_metrics: true,
        limited_plans: false
      )
      expect(copy.coupon_targets.map { [it.billable_metric_id, it.organization_id] })
        .to contain_exactly([live_metric.id, production.id], [copied_metric.id, production.id])
    end

    context "when a coupon without expiration keeps a past date" do
      before { coupon.update!(expiration: "no_expiration", expiration_at: 1.day.ago) }

      it "copies the coupon without the date" do
        expect(result).to be_success
        expect(result.item.record).to have_attributes(status: "active", expiration: "no_expiration", expiration_at: nil)
      end
    end

    context "when one targeted metric is deleted in the sandbox" do
      before { copied_metric_source.discard! }

      it "copies the coupon limited to the kept metric" do
        expect { result }.not_to change { production.billable_metrics.count }

        expect(result).to be_success
        expect(result.item.record.limited_billable_metrics).to be(true)
        expect(result.item.record.coupon_targets.map(&:billable_metric_id)).to eq([live_metric.id])
      end
    end
  end

  context "with a product category" do
    let(:item_type) { "product_category" }
    let(:id) { category.id }
    let(:category) { create(:product_category, organization: sandbox, code: "compute", name: "Compute") }
    let(:api) do
      create(:product, organization: sandbox, product_category: category, billable_metric: metric, code: "api", name: "API")
    end
    let(:seat) { create(:product, :fixed, organization: sandbox, product_category: category, code: "seat", name: "Seat") }
    let(:filter) { create(:product_filter, organization: sandbox, product: api, code: "eu_only", name: "EU only") }
    let(:api_card) { create(:rate_card, organization: sandbox, product: api, product_filter: filter, code: "api_eur") }
    let(:seat_card) { create(:rate_card, organization: sandbox, product: seat, code: "seat_eur") }
    let(:tax) { create(:tax, organization: sandbox, code: "vat_fr", name: "VAT FR", rate: 20) }

    around { |test| travel_to(Time.zone.parse("2026-11-23 10:30:00")) { test.run } }

    before do
      create(
        :product_filter_value,
        organization: sandbox,
        product_filter: filter,
        billable_metric_filter: metric.filters.find_by(key: "region"),
        value: "eu"
      )
      create(:rate_card_rate, organization: sandbox, rate_card: api_card, code: "launch", effective_from: 3.months.ago.beginning_of_day)
      create(
        :rate_card_rate,
        organization: sandbox,
        rate_card: api_card,
        code: "current",
        effective_from: 1.month.ago.beginning_of_day,
        rate_properties: {"amount" => "12"}
      )
      create(
        :rate_card_rate,
        organization: sandbox,
        rate_card: api_card,
        code: "next",
        effective_from: 1.month.from_now.beginning_of_day,
        rate_properties: {"amount" => "15"}
      )
      create(:rate_card_rate, organization: sandbox, rate_card: seat_card, code: "seat_rate", effective_from: 1.week.ago.beginning_of_day)
      create(:rate_card_applied_tax, rate_card: seat_card, tax:)
    end

    it "copies the category with its products, their rate cards and what they reference" do
      expect(result).to be_success

      live_category = production.product_categories.find_by!(code: "compute")
      expect(result.item).to eq(CopyToProduction::CopyService::Entry.new(item_type: "product_category", record: live_category))
      expect(live_category).to have_attributes(name: "Compute", description: category.description)

      live_api = production.products.find_by!(code: "api")
      expect(live_api).to have_attributes(
        name: "API",
        product_type: "metered",
        product_category: live_category,
        billable_metric: production.billable_metrics.find_by!(code: "api_calls")
      )
      expect(live_api.filters.map { [it.code, it.name] }).to eq([%w[eu_only EU\ only]])
      expect(live_api.filters.first.values.map { [it.billable_metric_filter.key, it.billable_metric_filter.organization_id, it.value] })
        .to eq([["region", production.id, "eu"]])
      expect(production.products.find_by!(code: "seat")).to have_attributes(product_type: "fixed", billable_metric: nil)

      live_api_card = production.rate_cards.find_by!(code: "api_eur")
      expect(live_api_card).to have_attributes(product: live_api, product_filter: live_api.filters.first, currency: "EUR")
      # The superseded launch rate stays in the sandbox; the current rate applies from the copy on.
      expect(live_api_card.rates.order(:effective_from).map { [it.code, it.effective_from, it.rate_properties] }).to eq(
        [
          ["current", Time.zone.parse("2026-11-23"), {"amount" => "12"}],
          ["next", Time.zone.parse("2026-12-23"), {"amount" => "15"}]
        ]
      )

      live_tax = production.taxes.find_by!(code: "vat_fr")
      expect(live_tax).to have_attributes(name: "VAT FR", rate: 20, applied_to_organization: false)
      expect(production.rate_cards.find_by!(code: "seat_eur").taxes).to eq([live_tax])
    end

    context "with activity logs", :capture_kafka_messages do
      let(:activity_log_env) do
        {
          "LAGO_CLICKHOUSE_ENABLED" => "true",
          "LAGO_KAFKA_BOOTSTRAP_SERVERS" => "kafka",
          "LAGO_KAFKA_ACTIVITY_LOGS_TOPIC" => "activity_logs"
        }
      end

      before { stub_const("ENV", ENV.to_h.merge(activity_log_env)) }

      it "logs the copy of each copied item but the tax" do
        result

        moves = kafka_messages.map { JSON.parse(it[:payload]) }.select { it["activity_type"].end_with?(".copied_to_production") }
        expect(moves.map { [it["activity_type"], it["organization_id"]] }).to eq(
          %w[product_category billable_metric product rate_card product rate_card].map { ["#{it}.copied_to_production", production.id] }
        )
      end
    end

    context "when production has metrics and taxes with the same codes" do
      let(:live_metric) { create(:billable_metric, organization: production, code: "api_calls") }
      let(:live_tax) { create(:tax, organization: production, code: "vat_fr") }

      before do
        create(:billable_metric_filter, billable_metric: live_metric, key: "region", values: %w[eu us])
        live_tax
      end

      it "reuses them without changing them" do
        expect { result }.not_to change { live_metric.reload.attributes }

        expect(result).to be_success
        expect(production.products.find_by!(code: "api").billable_metric).to eq(live_metric)
        expect(production.rate_cards.find_by!(code: "seat_eur").taxes).to eq([live_tax])
        expect(production.billable_metrics.count).to eq(1)
        expect(production.taxes.count).to eq(1)
      end
    end

    context "when a rate card is priced in a pricing unit", :premium do
      let(:pricing_unit) { create(:pricing_unit, organization: sandbox, code: "credits", name: "Credits", short_name: "CR") }

      before do
        seat_card.update!(applied_pricing_unit_code: pricing_unit.code)
        seat_card.rates.update_all(applied_pricing_unit_conversion_rate: 0.5, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      end

      it "copies the pricing unit before the rate card" do
        expect(result).to be_success

        expect(production.pricing_units.find_by!(code: "credits")).to have_attributes(name: "Credits", short_name: "CR")
        expect(production.rate_cards.find_by!(code: "seat_eur").rates.pluck(:applied_pricing_unit_conversion_rate)).to eq([0.5])
      end
    end
  end

  context "with a product" do
    let(:item_type) { "product" }
    let(:id) { product.id }
    let(:category) { create(:product_category, organization: sandbox, code: "compute") }
    let(:product) { create(:product, organization: sandbox, product_category: category, billable_metric: metric, code: "api") }

    before { create(:rate_card_rate, organization: sandbox, rate_card: create(:rate_card, organization: sandbox, product:, code: "api_eur")) }

    context "when its category is not live" do
      it "refuses the copy" do
        expect { result }.not_to change(Product, :count)

        expect(result).to be_failure
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
        expect(result.error.code).to eq("copy_to_production_parent_missing")
        expect(result.missing_parent).to eq(CopyToProduction::CopyService::Entry.new(item_type: "product_category", record: category))
      end
    end

    context "when its category is live" do
      let(:live_category) { create(:product_category, organization: production, code: "compute") }

      before { live_category }

      it "copies the product into it with its metric and rate cards" do
        expect(result).to be_success

        live_product = production.products.find_by!(code: "api")
        expect(result.item).to eq(CopyToProduction::CopyService::Entry.new(item_type: "product", record: live_product))
        expect(live_product.product_category).to eq(live_category)
        expect(live_product.rate_cards.sole.rates.count).to eq(1)
      end

      context "with a tiered rate" do
        # Stored as the create service saves it: each tier with the lower bound it starts at.
        let(:graduated_ranges) do
          [
            {"from_value" => 0, "to_value" => 10, "flat_amount" => "0", "per_unit_amount" => "1"},
            {"from_value" => 10, "to_value" => nil, "flat_amount" => "0", "per_unit_amount" => "0.5"}
          ]
        end

        before do
          create(:rate_card_rate, organization: sandbox, rate_model: "graduated",
            rate_properties: {"graduated_ranges" => graduated_ranges},
            rate_card: create(:rate_card, organization: sandbox, product:, code: "api_tiers"))
        end

        it "copies its tiers" do
          expect(result).to be_success

          live_rate = production.rate_cards.find_by!(code: "api_tiers").rates.sole
          expect(live_rate.rate_properties["graduated_ranges"]).to eq(graduated_ranges)
        end
      end

      context "with filters whose codes do not follow their creation order" do
        before do
          {"zone_b" => "us", "zone_a" => "eu"}.each do |code, value|
            filter = create(:product_filter, organization: sandbox, product:, code:)
            create(
              :product_filter_value,
              organization: sandbox,
              product_filter: filter,
              billable_metric_filter: metric.filters.find_by(key: "region"),
              value:
            )
          end
        end

        it "creates them in production in creation order, which filter precedence reads" do
          expect(result).to be_success

          live_filters = production.products.find_by!(code: "api").filters
          expect(live_filters.order(:created_at, :id).pluck(:code)).to eq(%w[zone_b zone_a])
        end
      end
    end

    context "when its category is live and its metric is deleted" do
      before do
        create(:product_category, organization: production, code: "compute")
        metric.discard!
      end

      it "refuses the copy without bringing the metric back" do
        expect { result }.not_to change { [Product.count, BillableMetric.count] }

        expect(result).to be_failure
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
        expect(result.error.code).to eq("copy_to_production_target_deleted")
      end
    end

    context "without a category" do
      let(:product) { create(:product, :standalone, organization: sandbox, billable_metric: metric, code: "api") }

      it "copies the product" do
        expect(result).to be_success

        expect(production.products.find_by!(code: "api").product_category).to be_nil
      end
    end
  end

  context "with an internal item type" do
    let(:item_type) { "tax" }
    let(:tax) { create(:tax, organization: sandbox) }
    let(:id) { tax.id }

    before { tax }

    it "answers not found" do
      expect { result }.not_to change(Tax, :count)

      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::NotFoundFailure)
    end
  end
end
