# frozen_string_literal: true

require "rails_helper"

RSpec.describe DatabaseMigrations::EnqueueChargeFilterCodeBackfillService do
  subject(:service) { described_class.call(poll_interval: 0) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:billable_metric) { create(:billable_metric, organization:) }
  let(:bm_filter) { create(:billable_metric_filter, billable_metric:, key: "region", values: %w[us eu]) }
  let(:charge) { create(:standard_charge, plan:, billable_metric:) }

  let_it_be(:plan) { create(:plan, organization:) }

  def build_filter(on, values, **attrs)
    filter = create(:charge_filter, charge: on, **attrs)
    create(:charge_filter_value, charge_filter: filter, billable_metric_filter: bm_filter, values:)
    filter
  end

  # An organization with nothing active is not billing, so its filters are not worth the work
  before { create(:subscription, organization:, status: :active) }

  describe "#call" do
    it "skips organizations with nothing active" do
      dormant = create(:organization)
      dormant_plan = create(:plan, organization: dormant)
      dormant_metric = create(:billable_metric, organization: dormant)
      dormant_charge = create(:standard_charge, plan: dormant_plan, billable_metric: dormant_metric)
      dormant_filter = create(:charge_filter, charge: dormant_charge)
      dormant_bm_filter = create(:billable_metric_filter, billable_metric: dormant_metric, key: "region", values: %w[us])
      create(:charge_filter_value, charge_filter: dormant_filter, billable_metric_filter: dormant_bm_filter, values: %w[us])

      expect { service }.not_to have_enqueued_job(DatabaseMigrations::BackfillChargeFilterCodesJob)
        .with(dormant_charge.id)
    end

    it "enqueues one job for a plan charge still missing a code" do
      build_filter(charge, ["us"])

      expect { service }.to have_enqueued_job(DatabaseMigrations::BackfillChargeFilterCodesJob)
        .with(charge.id)
        .once
    end

    # The walk is one cursor per organization, so it has to carry on into the next one
    it "hands out charges from every organization that is billing" do
      build_filter(charge, ["us"])

      other_organization = create(:organization)
      create(:subscription, organization: other_organization, status: :active)
      other_metric = create(:billable_metric, organization: other_organization)
      other_charge = create(:standard_charge, plan: create(:plan, organization: other_organization), billable_metric: other_metric)
      other_bm_filter = create(:billable_metric_filter, billable_metric: other_metric, key: "region", values: %w[us])
      create(:charge_filter_value, charge_filter: create(:charge_filter, charge: other_charge),
        billable_metric_filter: other_bm_filter, values: %w[us])

      expect { service }
        .to have_enqueued_job(DatabaseMigrations::BackfillChargeFilterCodesJob).with(charge.id).once
        .and have_enqueued_job(DatabaseMigrations::BackfillChargeFilterCodesJob).with(other_charge.id).once
    end

    it "hands out every charge that needs one" do
      other = create(:standard_charge, plan:, billable_metric:)
      build_filter(charge, ["us"])
      build_filter(other, ["eu"])

      expect { service }.to have_enqueued_job(DatabaseMigrations::BackfillChargeFilterCodesJob).twice
    end

    # An override can only take a code its plan already holds, so it is a later pass.
    it "ignores charges that override another" do
      child_plan = create(:plan, organization:, parent: plan)
      child_charge = create(:standard_charge, plan: child_plan, billable_metric:, parent: charge)
      build_filter(child_charge, ["us"])

      expect { service }.not_to have_enqueued_job(DatabaseMigrations::BackfillChargeFilterCodesJob)
    end

    it "ignores a charge whose filters already have codes" do
      build_filter(charge, ["us"]).update_column(:code, "already_set") # rubocop:disable Rails/SkipsModelValidations

      expect { service }.not_to have_enqueued_job(DatabaseMigrations::BackfillChargeFilterCodesJob)
    end

    it "ignores a charge with no filters at all" do
      create(:standard_charge, plan:, billable_metric:)

      expect { service }.not_to have_enqueued_job(DatabaseMigrations::BackfillChargeFilterCodesJob)
    end

    it "ignores discarded charges" do
      build_filter(charge, ["us"])
      charge.discard!

      expect { service }.not_to have_enqueued_job(DatabaseMigrations::BackfillChargeFilterCodesJob)
    end

    # A deleted plan is not billing anything, so its filters are not worth the work — and the
    # plan association is `with_discarded`, so without this they would come through
    it "ignores charges on a discarded plan" do
      build_filter(charge, ["us"])
      plan.discard!

      expect { service }.not_to have_enqueued_job(DatabaseMigrations::BackfillChargeFilterCodesJob)
    end

    it "walks past the end of a batch" do
      3.times { build_filter(create(:standard_charge, plan:, billable_metric:), ["us"]) }

      expect { described_class.call(batch_size: 2, poll_interval: 0) }
        .to have_enqueued_job(DatabaseMigrations::BackfillChargeFilterCodesJob).exactly(3).times
    end

    # The cursor is on charges, so the batch bounds what is read as well as what is handed out.
    # One plan holds 51,914 of them in production, and reading those in one go was what the
    # earlier plan-driven walk could not avoid.
    it "reads no more than a batch at a time" do
      3.times { build_filter(create(:standard_charge, plan:, billable_metric:), ["us"]) }
      queue = instance_double(Sidekiq::Queue, size: 0)
      allow(Sidekiq::Queue).to receive(:new).and_return(queue)

      described_class.call(batch_size: 1, poll_interval: 0)

      # one check per batch, and a batch is one charge
      expect(queue).to have_received(:size).at_least(3).times
    end

    # The queue is shared, so the walk has to stop pushing rather than bury everything else.
    it "waits for the queue to drop below the limit before handing out more" do
      build_filter(charge, ["us"])
      queue = instance_double(Sidekiq::Queue)
      allow(Sidekiq::Queue).to receive(:new).and_return(queue)
      allow(queue).to receive(:size).and_return(5_000, 0)

      described_class.call(max_queue_size: 10, poll_interval: 0)

      expect(queue).to have_received(:size).at_least(:twice)
    end
  end
end
