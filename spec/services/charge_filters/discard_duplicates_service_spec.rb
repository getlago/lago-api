# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChargeFilters::DiscardDuplicatesService do
  subject(:service) { described_class.call(organization:, dry_run:, **options) }

  let(:organization) { create(:organization) }
  let(:billable_metric) { create(:billable_metric, organization:, code: "api_pages") }
  let(:plan) { create(:plan, organization:) }
  let(:charge) { create(:standard_charge, plan:, billable_metric:, properties: {"amount" => "0.01"}) }
  let(:dry_run) { false }
  let(:options) { {} }

  # The key every collapsed filter ends up matching on.
  let(:model_key) do
    create(:billable_metric_filter, billable_metric:, organization:, key: "model", values: %w[ocr])
  end

  # The key the customer deletes, which is what broadens the filter that depends on it.
  let(:training_key) do
    create(:billable_metric_filter, billable_metric:, organization:, key: "training", values: %w[supporter])
  end

  # Builds a charge filter with the given conditions, e.g. {model_key => %w[ocr]}.
  def create_charge_filter(conditions, amount:, invoice_display_name: nil, charge: self.charge)
    filter = create(
      :charge_filter,
      charge:,
      organization:,
      invoice_display_name:,
      properties: {"amount" => amount}
    )

    conditions.each do |billable_metric_filter, values|
      create(:charge_filter_value, charge_filter: filter, billable_metric_filter:, organization:, values:)
    end

    filter
  end

  # Applies a real billable metric filter edit, which is how filters broaden in production.
  # Any key absent from the params is deleted; any value absent from a key's list is removed.
  def edit_billable_metric_filters(params)
    BillableMetricFilters::CreateOrUpdateBatchService.call!(
      billable_metric: billable_metric.reload,
      filters_params: params
    )
  end

  describe "#call" do
    context "when a filter lost a condition and now matches the same predicate as a sibling" do
      # The ING-536 shape. Two filters priced differently for two different slices of usage:
      #   stale:    model=ocr AND training=supporter  @ 0.00136
      #   intended: model=ocr                         @ 0.0017
      # Deleting the training key leaves the stale filter alive matching model=ocr alone, so both
      # filters now match the same events and the usage is billed twice.
      let!(:stale) do
        create_charge_filter(
          {model_key => %w[ocr], training_key => %w[supporter]},
          amount: "0.00136",
          invoice_display_name: "ocr • Supporter"
        )
      end

      let!(:intended) { create_charge_filter({model_key => %w[ocr]}, amount: "0.0017") }

      before { edit_billable_metric_filters([{key: "model", values: %w[ocr]}]) }

      it "discards the broadened filter and keeps the intact one" do
        expect(service).to be_success
        expect(service.discarded_filter_ids).to eq([stale.id])
        expect(stale.reload).to be_discarded
        expect(intended.reload).not_to be_discarded
      end

      it "discards the condition rows of the discarded filter" do
        service

        expect(stale.values.with_discarded.where(deleted_at: nil)).to be_empty
      end

      it "reports the group with the keeper it selected" do
        group = service.duplicate_groups.sole

        expect(group.charge_id).to eq(charge.id)
        expect(group.metric_code).to eq("api_pages")
        expect(group.keeper).to eq(intended)
        expect(group.filters_to_discard).to eq([stale])
        expect(group).not_to be_skipped
      end

      it "expires the usage cache of the plan's subscriptions" do
        subscription = create(:subscription, plan:, organization:)
        allow(Subscriptions::ChargeCacheService).to receive(:expire_for_subscriptions)

        service

        expect(Subscriptions::ChargeCacheService).to have_received(:expire_for_subscriptions)
          .with([subscription.id])
      end

      it "marks the draft invoices of the billable metric to be refreshed" do
        # The billable metric edit in the before block enqueues one of these too.
        ActiveJob::Base.queue_adapter.enqueued_jobs.clear

        service

        expect(BillableMetricFilters::RefreshDraftInvoicesJob).to have_been_enqueued
          .with(billable_metric.id)
      end

      context "when dry_run is true" do
        let(:dry_run) { true }

        it "reports the group without discarding anything" do
          expect(service.duplicate_groups.sole.filters_to_discard).to eq([stale])
          expect(service.discarded_filter_ids).to be_empty
          expect(stale.reload).not_to be_discarded
        end
      end
    end

    context "when every filter in the group lost a condition" do
      # Both filters broadened onto model=ocr, so nothing is left to tell us which price was
      # intended. The group is reported and left alone rather than repaired on a guess.
      let(:zone_key) do
        create(:billable_metric_filter, billable_metric:, organization:, key: "zone", values: %w[global])
      end

      let!(:supporter_filter) do
        create_charge_filter({model_key => %w[ocr], training_key => %w[supporter]}, amount: "0.00136")
      end

      let!(:global_filter) do
        create_charge_filter({model_key => %w[ocr], zone_key => %w[global]}, amount: "0.0017")
      end

      before { edit_billable_metric_filters([{key: "model", values: %w[ocr]}]) }

      it "skips the group and discards nothing" do
        expect(service.duplicate_groups.sole.skip_reason).to eq("every filter lost a condition, keeper is ambiguous")
        expect(service.discarded_filter_ids).to be_empty
        expect(supporter_filter.reload).not_to be_discarded
        expect(global_filter.reload).not_to be_discarded
      end
    end

    context "when a condition row was trimmed in place instead of removed" do
      # Removing `global` from a key that still has other values rewrites the condition row
      # in place: {zone: [eu, global]} becomes {zone: [eu]}, which collapses onto a filter that
      # already matched zone=eu. The trim leaves no deleted_at behind, so both filters look
      # intact and the keeper falls back to the oldest.
      let(:zone_key) do
        create(:billable_metric_filter, billable_metric:, organization:, key: "zone", values: %w[eu global])
      end

      let!(:older) { create_charge_filter({zone_key => %w[eu global]}, amount: "0.5") }
      let!(:newer) { create_charge_filter({zone_key => %w[eu]}, amount: "0.9") }

      before do
        older.update!(created_at: 2.days.ago)
        newer.update!(created_at: 1.day.ago)
        edit_billable_metric_filters([{key: "zone", values: %w[eu]}])
      end

      it "keeps the oldest filter" do
        expect(service.discarded_filter_ids).to eq([newer.id])
        expect(older.reload).not_to be_discarded
      end

      it "freezes the invoice display name of the discarded filter" do
        # display_name reads the kept condition rows, so without this the label would render
        # blank on any invoice PDF regenerated after the discard.
        service

        expect(newer.reload.invoice_display_name).to eq("eu")
      end
    end

    context "when two filters express the same predicate through the ALL values sentinel" do
      # model=[__ALL_FILTER_VALUES__] and model=[ocr, vision] are the same predicate once the
      # sentinel is expanded, so they are duplicates even though the stored values differ.
      let(:model_key) do
        create(:billable_metric_filter, billable_metric:, organization:, key: "model", values: %w[ocr vision])
      end

      let!(:sentinel_filter) do
        create_charge_filter({model_key => [ChargeFilterValue::ALL_FILTER_VALUES]}, amount: "1")
      end

      let!(:explicit_filter) { create_charge_filter({model_key => %w[ocr vision]}, amount: "2") }

      before do
        sentinel_filter.update!(created_at: 2.days.ago)
        explicit_filter.update!(created_at: 1.day.ago)
      end

      it "detects the duplicate and keeps the oldest filter" do
        expect(service.duplicate_groups.size).to eq(1)
        expect(service.discarded_filter_ids).to eq([explicit_filter.id])
        expect(sentinel_filter.reload).not_to be_discarded
      end
    end

    context "when the filters have different predicates" do
      let(:model_key) do
        create(:billable_metric_filter, billable_metric:, organization:, key: "model", values: %w[ocr vision])
      end

      let!(:ocr_filter) { create_charge_filter({model_key => %w[ocr]}, amount: "1") }
      let!(:vision_filter) { create_charge_filter({model_key => %w[vision]}, amount: "2") }

      it "finds no duplicate group" do
        expect(service.duplicate_groups).to be_empty
        expect(service.discarded_filter_ids).to be_empty
        expect(ocr_filter.reload).not_to be_discarded
        expect(vision_filter.reload).not_to be_discarded
      end
    end

    context "when another organization has duplicates" do
      let(:other_organization) { create(:organization) }
      let(:other_billable_metric) { create(:billable_metric, organization: other_organization) }
      let(:other_plan) { create(:plan, organization: other_organization) }

      let(:other_charge) do
        create(:standard_charge, plan: other_plan, billable_metric: other_billable_metric, properties: {"amount" => "0.01"})
      end

      let(:other_model_key) do
        create(:billable_metric_filter, billable_metric: other_billable_metric, organization: other_organization, key: "model", values: %w[ocr])
      end

      let!(:other_filters) do
        2.times.map do |index|
          filter = create(:charge_filter, charge: other_charge, organization: other_organization, properties: {"amount" => index.to_s})
          create(:charge_filter_value, charge_filter: filter, billable_metric_filter: other_model_key, organization: other_organization, values: %w[ocr])
          filter
        end
      end

      it "leaves them untouched" do
        expect(service.duplicate_groups).to be_empty
        expect(other_filters.map { it.reload.discarded? }).to eq([false, false])
      end
    end

    context "when a plan is given" do
      # Canary mode: repair one plan, verify, then sweep the rest.
      let(:options) { {plan: other_plan} }
      let(:other_plan) { create(:plan, organization:) }

      let(:other_charge) do
        create(:standard_charge, plan: other_plan, billable_metric:, properties: {"amount" => "0.01"})
      end

      let!(:duplicates_on_plan) do
        2.times.map { |index| create_charge_filter({model_key => %w[ocr]}, amount: index.to_s) }
      end

      let!(:duplicates_on_other_plan) do
        2.times.map do |index|
          create_charge_filter({model_key => %w[ocr]}, amount: index.to_s, charge: other_charge)
        end
      end

      it "only repairs the given plan" do
        expect(service.duplicate_groups.sole.charge_id).to eq(other_charge.id)
        expect(duplicates_on_other_plan.count { it.reload.discarded? }).to eq(1)
        expect(duplicates_on_plan.count { it.reload.discarded? }).to eq(0)
      end
    end

    context "when the keeper strategy is unknown" do
      let(:options) { {keeper_strategy: "cheapest"} }

      it "returns a validation failure" do
        expect(service).not_to be_success
        expect(service.error).to be_a(BaseService::ValidationFailure)
        expect(service.error.messages[:keeper_strategy]).to eq(
          ["must be one of intact_then_oldest, oldest, newest"]
        )
      end
    end

    context "when the keeper strategy is newest" do
      let(:options) { {keeper_strategy: "newest"} }

      let!(:older) { create_charge_filter({model_key => %w[ocr]}, amount: "1") }
      let!(:newer) { create_charge_filter({model_key => %w[ocr]}, amount: "2") }

      before do
        older.update!(created_at: 2.days.ago)
        newer.update!(created_at: 1.day.ago)
      end

      it "keeps the newest filter regardless of removed conditions" do
        expect(service.discarded_filter_ids).to eq([older.id])
        expect(newer.reload).not_to be_discarded
      end
    end
  end
end
