# frozen_string_literal: true

require "rails_helper"

RSpec.describe DatabaseMigrations::EnqueueChildChargeFilterCodeBackfillService do
  subject(:service) { described_class.call(poll_interval: 0) }

  let(:organization) { create(:organization) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:bm_filter) { create(:billable_metric_filter, billable_metric:, key: "region", values: %w[us eu]) }

  let(:plan) { create(:plan, organization:) }
  let(:charge) { create(:standard_charge, plan:, billable_metric:) }

  let(:us_code) { ChargeFilter.generate_code({"region" => ["us"]}) }

  def build_filter(on, values, code: nil)
    filter = create(:charge_filter, charge: on)
    create(:charge_filter_value, charge_filter: filter, billable_metric_filter: bm_filter, values:)
    filter.update_column(:code, code) if code # rubocop:disable Rails/SkipsModelValidations
    filter
  end

  before { create(:subscription, organization:, status: :active) }

  describe "#call" do
    it "enqueues one job for a plan charge whose filters have codes" do
      build_filter(charge, ["us"], code: us_code)

      expect { service }.to have_enqueued_job(DatabaseMigrations::BackfillChildChargeFilterCodesJob)
        .with(charge.id)
        .once
    end

    # A parent the first pass refused to decide has nothing to hand down
    it "ignores a plan charge still without codes" do
      build_filter(charge, ["us"])

      expect { service }.not_to have_enqueued_job(DatabaseMigrations::BackfillChildChargeFilterCodesJob)
    end

    it "ignores a charge with no filters at all" do
      create(:standard_charge, plan:, billable_metric:)

      expect { service }.not_to have_enqueued_job(DatabaseMigrations::BackfillChildChargeFilterCodesJob)
    end

    # The job is handed the parent, never the override
    it "ignores charges that override another" do
      child_plan = create(:plan, organization:, parent: plan)
      child_charge = create(:standard_charge, plan: child_plan, billable_metric:, parent: charge)
      build_filter(child_charge, ["us"], code: us_code)

      expect { service }.not_to have_enqueued_job(DatabaseMigrations::BackfillChildChargeFilterCodesJob)
    end

    it "ignores discarded charges" do
      build_filter(charge, ["us"], code: us_code)
      charge.discard!

      expect { service }.not_to have_enqueued_job(DatabaseMigrations::BackfillChildChargeFilterCodesJob)
    end

    it "skips organizations with nothing active" do
      dormant = create(:organization)
      dormant_metric = create(:billable_metric, organization: dormant)
      dormant_charge = create(:standard_charge, plan: create(:plan, organization: dormant), billable_metric: dormant_metric)
      dormant_filter = create(:charge_filter, charge: dormant_charge)
      create(
        :charge_filter_value,
        charge_filter: dormant_filter,
        billable_metric_filter: create(:billable_metric_filter, billable_metric: dormant_metric, key: "region", values: %w[us]),
        values: %w[us]
      )
      dormant_filter.update_column(:code, us_code) # rubocop:disable Rails/SkipsModelValidations

      expect { service }.not_to have_enqueued_job(DatabaseMigrations::BackfillChildChargeFilterCodesJob)
        .with(dormant_charge.id)
    end

    it "walks past the end of a batch" do
      3.times { build_filter(create(:standard_charge, plan:, billable_metric:), ["us"], code: us_code) }

      expect { described_class.call(batch_size: 2, poll_interval: 0) }
        .to have_enqueued_job(DatabaseMigrations::BackfillChildChargeFilterCodesJob).exactly(3).times
    end

    it "waits for the queue to drop below the limit before handing out more" do
      build_filter(charge, ["us"], code: us_code)
      queue = instance_double(Sidekiq::Queue)
      allow(Sidekiq::Queue).to receive(:new).and_return(queue)
      allow(queue).to receive(:size).and_return(5_000, 0)

      described_class.call(max_queue_size: 10, poll_interval: 0)

      expect(queue).to have_received(:size).at_least(:twice)
    end
  end
end
