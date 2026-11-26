# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::ContractAlert do
  subject(:alert) { build(:contract_alert, organization:, contract_external_id: contract.external_id) }

  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:customer) { create_default(:customer) }
  let_it_be(:contract) { create(:contract) }

  let(:llm_tokens) { build_stubbed(:product, organization:) }
  let(:opus) { build_stubbed(:product_filter, organization:, product: llm_tokens) }
  let(:sonnet) { build_stubbed(:product_filter, organization:, product: llm_tokens) }
  let(:video_minutes) { build_stubbed(:product, organization:) }
  let(:platform) { build_stubbed(:product, :fixed, organization:) }

  let(:opus_card) { card_of(llm_tokens, opus) }
  let(:sonnet_card) { card_of(llm_tokens, sonnet) }
  let(:llm_tokens_card) { card_of(llm_tokens) }
  let(:video_minutes_card) { card_of(video_minutes) }
  let(:platform_card) { card_of(platform) }
  let(:opus_slice) { "#{llm_tokens.id}/#{opus.id}" }
  let(:sonnet_slice) { "#{llm_tokens.id}/#{sonnet.id}" }

  let(:usage) do
    contract_usage(
      card_usage(opus_card, "2026-11-01", units: 600_000, amount_cents: 300_00),
      card_usage(sonnet_card, "2026-11-02", units: 500_000, amount_cents: 200_00),
      card_usage(llm_tokens_card, "2026-11-01", units: 10_000, amount_cents: 50_00),
      card_usage(video_minutes_card, "2026-11-01", units: 90, amount_cents: 150_00),
      card_usage(platform_card, "2026-01-01", units: 1, amount_cents: 500_00)
    )
  end

  def card_of(product, product_filter = nil)
    rate_card = build_stubbed(:rate_card, organization:, product:, product_filter:)
    build_stubbed(:contract_rate_card, organization:, contract:, rate_card:)
  end

  def card_usage(contract_rate_card, started_at, units:, amount_cents:)
    instance_double(RateCardUsage, contract_rate_card:, started_at: Time.zone.parse(started_at), units: BigDecimal(units), amount_cents:)
  end

  def contract_usage(*rate_card_usages, on: contract)
    Contracts::CurrentUsageService::Result.new.tap do
      it.contract = on
      it.rate_card_usages = rate_card_usages
    end
  end

  describe "enums" do
    it do
      expect(alert).to define_enum_for(:direction)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(increasing: "increasing", decreasing: "decreasing")
    end
  end

  describe "associations" do
    it do
      expect(alert).to belong_to(:organization)
      expect(alert).to belong_to(:product).optional
      expect(alert).to belong_to(:product_filter).optional
      expect(alert).to have_many(:thresholds).class_name("UsageMonitoring::ContractAlertThreshold")
        .dependent(:delete_all).inverse_of(:alert)
      expect(alert).to have_many(:triggered_alerts).class_name("UsageMonitoring::ContractTriggeredAlert")
        .conditions(kind: "triggered")
      expect(alert).to have_many(:all_triggered_alerts).class_name("UsageMonitoring::ContractTriggeredAlert")
        .inverse_of(:alert)
    end

    it "resolves a discarded product and product filter" do
      product_filter = create(:product_filter)
      product = product_filter.product
      alert = create(:contract_usage_units_alert, contract_external_id: contract.external_id, product:, product_filter:)

      product_filter.discard!
      product.discard!

      expect(described_class.find(alert.id)).to have_attributes(product:, product_filter:)
    end
  end

  describe "validations" do
    it do
      expect(alert).to validate_presence_of(:code)
      expect(alert).to validate_presence_of(:contract_external_id)
      expect(alert).to validate_inclusion_of(:alert_type).in_array(%w[usage_amount usage_units])
    end

    describe "scope validation" do
      let(:product) { create(:product) }
      let(:product_filter) { create(:product_filter, product:) }

      it "accepts a product filter of its product" do
        alert.assign_attributes(product:, product_filter:)

        expect(alert).to be_valid
      end

      it "refuses a product filter without its product" do
        alert.product_filter = product_filter

        expect(alert).to be_invalid
        expect(alert.errors[:product]).to eq(["value_is_mandatory"])
      end

      it "refuses a product filter of another product" do
        alert.assign_attributes(product: create(:product), product_filter:)

        expect(alert).to be_invalid
        expect(alert.errors[:product_filter]).to eq(["value_is_invalid"])
      end

      it "accepts with_product_filters on a product" do
        alert.assign_attributes(product:, with_product_filters: true)

        expect(alert).to be_valid
      end

      it "refuses with_product_filters without a product" do
        alert.with_product_filters = true

        expect(alert).to be_invalid
        expect(alert.errors[:with_product_filters]).to eq(["value_is_invalid"])
      end

      it "refuses with_product_filters on a product filter" do
        alert.assign_attributes(product:, product_filter:, with_product_filters: true)

        expect(alert).to be_invalid
        expect(alert.errors[:with_product_filters]).to eq(["value_is_invalid"])
      end
    end
  end

  describe ".find_sti_class" do
    it "returns the class of each alert type" do
      expect(described_class.find_sti_class("usage_amount")).to eq(UsageMonitoring::ContractUsageAmountAlert)
      expect(described_class.find_sti_class("usage_units")).to eq(UsageMonitoring::ContractUsageUnitsAlert)
    end

    it "raises KeyError for an unknown alert type" do
      expect { described_class.find_sti_class("current_usage_amount") }.to raise_error(KeyError)
    end
  end

  describe ".sti_name" do
    it "returns the alert type of each subclass" do
      expect(UsageMonitoring::ContractUsageAmountAlert.sti_name).to eq("usage_amount")
      expect(UsageMonitoring::ContractUsageUnitsAlert.sti_name).to eq("usage_units")
    end
  end

  describe "#find_thresholds_crossed" do
    let(:alert) do
      create(
        :contract_alert,
        contract_external_id: contract.external_id,
        thresholds: [10, 30, 50],
        recurring_threshold: 100,
        previous_value: 33
      )
    end

    it "returns the one-time and recurring thresholds between previous_value and current" do
      # 50 is the last one-time threshold, then one recurring step of 100 at 150, 250 and 350
      expect(alert.find_thresholds_crossed(351)).to eq([50, 150, 250, 350])
    end

    it "records the crossing in the contract triggered alerts" do
      crossed = alert.find_thresholds_crossed(351)
      triggered_alert = alert.all_triggered_alerts.create!(
        organization:,
        alertable: contract,
        current_value: 351,
        previous_value: alert.previous_value,
        crossed_thresholds: alert.formatted_crossed_thresholds(crossed),
        triggered_at: Time.current
      )

      expect(alert.triggered_alerts).to eq([triggered_alert])
      expect(triggered_alert.reload).to have_attributes(contract:, alert:)
      expect(triggered_alert.crossed_thresholds).to eq([
        {"code" => "warn50", "value" => "50.0", "recurring" => false},
        {"code" => "rec", "value" => "150.0", "recurring" => true},
        {"code" => "rec", "value" => "250.0", "recurring" => true},
        {"code" => "rec", "value" => "350.0", "recurring" => true}
      ])
      expect(alert.recorded_alarm_codes).to eq(Set["warn50", "rec"])
    end
  end

  describe "#cards_in_scope" do
    subject(:cards) { alert.cards_in_scope(usage).map(&:contract_rate_card) }

    it "keeps every metered card on the whole contract" do
      expect(cards).to eq([opus_card, sonnet_card, llm_tokens_card, video_minutes_card])
    end

    context "with a product" do
      let(:alert) { build(:contract_usage_units_alert, contract_external_id: contract.external_id, product: llm_tokens) }

      it "keeps its default card only" do
        expect(cards).to eq([llm_tokens_card])
      end

      context "with its filters" do
        let(:alert) do
          build(:contract_usage_units_alert, contract_external_id: contract.external_id, product: llm_tokens, with_product_filters: true)
        end

        it "keeps its filter cards and its default card" do
          expect(cards).to eq([opus_card, sonnet_card, llm_tokens_card])
        end
      end
    end

    context "with a product filter" do
      let(:alert) do
        build(:contract_usage_units_alert, contract_external_id: contract.external_id, product: llm_tokens, product_filter: opus)
      end

      it "keeps the card of that filter" do
        expect(cards).to eq([opus_card])
      end
    end
  end

  describe "#find_value" do
    subject(:value) { alert.find_value(usage) }

    it "sums the amount of every metered card of the whole contract" do
      # opus + sonnet + llm_tokens default + video_minutes, without platform's fixed 500_00
      expect(value).to eq(300_00 + 200_00 + 50_00 + 150_00)
    end

    context "with units of a product" do
      let(:alert) { build(:contract_usage_units_alert, contract_external_id: contract.external_id, product: llm_tokens) }

      it "returns the units of its default card, the events no filter matches" do
        expect(value).to eq(10_000)
      end

      context "with its filters" do
        let(:alert) do
          build(:contract_usage_units_alert, contract_external_id: contract.external_id, product: llm_tokens, with_product_filters: true)
        end

        it "sums the units of its filter cards and of its default card" do
          # opus + sonnet + the events no filter matches
          expect(value).to eq(600_000 + 500_000 + 10_000)
        end
      end

      context "when the contract prices the product through its filters only" do
        let(:usage) do
          contract_usage(
            card_usage(opus_card, "2026-11-01", units: 600_000, amount_cents: 300_00),
            card_usage(sonnet_card, "2026-11-02", units: 500_000, amount_cents: 200_00)
          )
        end

        it "returns nil, so the alert is skipped" do
          expect(value).to be_nil
        end
      end
    end

    context "with units of a product filter" do
      let(:alert) do
        build(:contract_usage_units_alert, contract_external_id: contract.external_id, product: llm_tokens, product_filter: opus)
      end

      it "returns the units of that filter's card" do
        expect(value).to eq(600_000)
      end
    end

    context "when no card prices the scope" do
      let(:alert) { build(:contract_usage_units_alert, contract_external_id: contract.external_id, product: llm_tokens) }
      let(:usage) { contract_usage(card_usage(video_minutes_card, "2026-11-01", units: 90, amount_cents: 150_00)) }

      it "returns nil, so the alert is skipped rather than evaluated at 0" do
        expect(value).to be_nil
      end
    end
  end

  describe "#windows_in_scope" do
    subject(:windows) { alert.windows_in_scope(usage) }

    let(:alert) do
      build(:contract_usage_units_alert, contract_external_id: contract.external_id, product: llm_tokens, with_product_filters: true)
    end
    let(:usage) do
      contract_usage(
        card_usage(opus_card, "2026-11-01", units: 600_000, amount_cents: 300_00),
        card_usage(sonnet_card, "2026-11-09", units: 0, amount_cents: 0),
        card_usage(video_minutes_card, "2026-11-01", units: 90, amount_cents: 150_00)
      )
    end

    it "keys each card in scope by its product and filter, with the start of its window and its value, cards without usage included" do
      expect(windows).to eq(
        opus_slice => {"started_at" => "2026-11-01T00:00:00.000000", "value" => "600000.0"},
        sonnet_slice => {"started_at" => "2026-11-09T00:00:00.000000", "value" => "0.0"}
      )
    end

    context "with a default card" do
      let(:usage) { contract_usage(card_usage(llm_tokens_card, "2026-11-01", units: 10_000, amount_cents: 50_00)) }

      it "keys it by its product" do
        expect(windows).to eq(llm_tokens.id => {"started_at" => "2026-11-01T00:00:00.000000", "value" => "10000.0"})
      end
    end

    context "when the customer has a timezone" do
      let(:usage) do
        customer = build_stubbed(:customer, timezone: "Asia/Tokyo")
        contract_usage(
          card_usage(opus_card, "2026-10-31T15:00:00Z", units: 600_000, amount_cents: 300_00),
          on: build_stubbed(:contract, customer:)
        )
      end

      it "gives the start of the window in the customer's local time" do
        expect(windows).to eq(opus_slice => {"started_at" => "2026-11-01T00:00:00.000000", "value" => "600000.0"})
      end
    end

    context "when a card meters a recurring metric" do
      let(:llm_tokens) do
        build_stubbed(:product, organization:, billable_metric: build_stubbed(:billable_metric, :recurring, organization:))
      end

      it "gives it no window start, as its usage carries over renewals" do
        expect(windows).to eq(
          opus_slice => {"started_at" => nil, "value" => "600000.0"},
          sonnet_slice => {"started_at" => nil, "value" => "0.0"}
        )
      end
    end
  end

  describe "#same_window?" do
    let(:alert) do
      build(
        :contract_alert,
        contract_external_id: contract.external_id,
        previous_windows: {
          opus_slice => {"started_at" => "2026-11-01T00:00:00.000000", "value" => "900000.0"},
          sonnet_slice => {"started_at" => nil, "value" => "120.0"}
        }
      )
    end

    it "is true while the card measures the window stored for it" do
      expect(alert.same_window?(opus_slice, {"started_at" => "2026-11-01T00:00:00.000000", "value" => "950000.0"})).to be(true)
    end

    it "is false once the card started a new window" do
      expect(alert.same_window?(opus_slice, {"started_at" => "2026-12-01T00:00:00.000000", "value" => "5000.0"})).to be(false)
    end

    it "is false once no card of the slice is in scope" do
      expect(alert.same_window?(opus_slice, nil)).to be(false)
    end

    it "is true for a card on a recurring metric, which has no window" do
      expect(alert.same_window?(sonnet_slice, {"started_at" => nil, "value" => "80.0"})).to be(true)
    end

    it "is false for a card stored by no evaluation" do
      expect(alert.same_window?(llm_tokens.id, {"started_at" => nil, "value" => "80.0"})).to be(false)
    end
  end
end
