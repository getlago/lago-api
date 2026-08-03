# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChargeFilters::CascadeDispatcher do
  let(:organization) { create(:organization) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:charge) { create(:standard_charge, plan:, billable_metric:) }

  let(:us_values) { {"region" => ["us"]} }
  let(:eu_values) { {"region" => ["eu"]} }

  describe ".call" do
    context "when a filter is added" do
      let(:before) { [] }
      let(:after) do
        [{values: us_values, properties: {"amount" => "10"}, invoice_display_name: "US"}]
      end

      it "enqueues a create cascade job" do
        expect {
          described_class.call(charge:, before:, after:)
        }.to have_enqueued_job(ChargeFilters::CascadeJob).with(
          charge.id, "create", us_values, nil, {"amount" => "10"}, "US"
        )
      end
    end

    context "when a filter is removed" do
      let(:before) do
        [{values: us_values, properties: {"amount" => "10"}, invoice_display_name: "US"}]
      end
      let(:after) { [] }

      it "enqueues a destroy cascade job" do
        expect {
          described_class.call(charge:, before:, after:)
        }.to have_enqueued_job(ChargeFilters::CascadeJob).with(
          charge.id, "destroy", us_values, {"amount" => "10"}, nil, "US"
        )
      end
    end

    context "when a filter's properties change" do
      let(:before) do
        [{values: us_values, properties: {"amount" => "10"}, invoice_display_name: "US"}]
      end
      let(:after) do
        [{values: us_values, properties: {"amount" => "15"}, invoice_display_name: "US"}]
      end

      it "enqueues an update cascade job carrying both old and new properties" do
        expect {
          described_class.call(charge:, before:, after:)
        }.to have_enqueued_job(ChargeFilters::CascadeJob).with(
          charge.id, "update", us_values, {"amount" => "10"}, {"amount" => "15"}, "US"
        )
      end
    end

    context "when a filter's invoice_display_name changes" do
      let(:before) do
        [{values: us_values, properties: {"amount" => "10"}, invoice_display_name: "US"}]
      end
      let(:after) do
        [{values: us_values, properties: {"amount" => "10"}, invoice_display_name: "US region"}]
      end

      it "enqueues an update cascade job with the new display name" do
        expect {
          described_class.call(charge:, before:, after:)
        }.to have_enqueued_job(ChargeFilters::CascadeJob).with(
          charge.id, "update", us_values, {"amount" => "10"}, {"amount" => "10"}, "US region"
        )
      end
    end

    context "when a filter is unchanged" do
      let(:filter) { {values: us_values, properties: {"amount" => "10"}, invoice_display_name: "US"} }
      let(:before) { [filter] }
      let(:after) { [filter] }

      it "does not enqueue any cascade job" do
        expect {
          described_class.call(charge:, before:, after:)
        }.not_to have_enqueued_job(ChargeFilters::CascadeJob)
      end
    end

    # A charge can still hold several filters on one predicate from before collapsed
    # filters were discarded. Whatever happens to them, the override has to end up
    # with the same single filter the plan does.
    context "when several filters share a predicate" do
      let(:filter) { {values: us_values, properties: {"amount" => "10"}, invoice_display_name: "US"} }
      let(:duplicate) { {values: us_values, properties: {"amount" => "20"}, invoice_display_name: "US bis"} }

      let(:before) { [filter, duplicate] }

      context "when one is kept unchanged" do
        let(:after) { [filter] }

        it "enqueues an update cascade job so the duplicates are reconciled" do
          expect {
            described_class.call(charge:, before:, after:)
          }.to have_enqueued_job(ChargeFilters::CascadeJob).with(
            charge.id, "update", us_values, {"amount" => "10"}, {"amount" => "10"}, "US"
          ).once
        end
      end

      context "when one is kept and changed" do
        let(:after) { [{values: us_values, properties: {"amount" => "15"}, invoice_display_name: "US"}] }

        it "enqueues a single update cascade job carrying the new properties" do
          expect {
            described_class.call(charge:, before:, after:)
          }.to have_enqueued_job(ChargeFilters::CascadeJob).with(
            charge.id, "update", us_values, {"amount" => "10"}, {"amount" => "15"}, "US"
          ).once
        end
      end

      context "when none is kept" do
        let(:after) { [] }

        it "enqueues a single destroy cascade job for the predicate" do
          expect {
            described_class.call(charge:, before:, after:)
          }.to have_enqueued_job(ChargeFilters::CascadeJob).with(
            charge.id, "destroy", us_values, {"amount" => "10"}, nil, "US"
          ).once
        end
      end

      context "when three share it and two are kept with changes" do
        let(:third) { {values: us_values, properties: {"amount" => "30"}, invoice_display_name: "US ter"} }
        let(:before) { [filter, duplicate, third] }
        let(:after) do
          [
            {values: us_values, properties: {"amount" => "11"}, invoice_display_name: "US"},
            {values: us_values, properties: {"amount" => "22"}, invoice_display_name: "US bis"}
          ]
        end

        # The first `after` filter consumes the whole group, so the second falls into
        # the create branch. CascadeService only creates when nothing matches, so the
        # child converges on the first one and the extras are discarded with it.
        it "enqueues an update for the first and a create the child ignores" do
          expect {
            described_class.call(charge:, before:, after:)
          }.to have_enqueued_job(ChargeFilters::CascadeJob).with(
            charge.id, "update", us_values, {"amount" => "10"}, {"amount" => "11"}, "US"
          ).and have_enqueued_job(ChargeFilters::CascadeJob).with(
            charge.id, "create", us_values, nil, {"amount" => "22"}, "US bis"
          )
        end

        it "enqueues no destroy job" do
          expect {
            described_class.call(charge:, before:, after:)
          }.not_to have_enqueued_job(ChargeFilters::CascadeJob).with(
            charge.id, "destroy", any_args
          )
        end
      end

      # Convergence itself is asserted in ChargeFilters::CascadeService — here we only
      # check the predicate is still cascaded rather than skipped as unchanged
      context "when both are kept" do
        let(:after) { [filter, duplicate] }

        it "enqueues an update cascade job for the predicate" do
          expect {
            described_class.call(charge:, before:, after:)
          }.to have_enqueued_job(ChargeFilters::CascadeJob).with(
            charge.id, "update", us_values, {"amount" => "10"}, {"amount" => "10"}, "US"
          )
        end
      end
    end

    # The shape a real plan ends up in: several predicates carrying duplicates, each
    # going a different way in one edit
    context "with duplicates on several predicates changing at once" do
      let(:asia_values) { {"region" => ["asia"]} }
      let(:ca_values) { {"region" => ["ca"]} }

      let(:before) do
        [
          # us: two filters, one kept and repriced
          {values: us_values, properties: {"amount" => "10"}, invoice_display_name: "US"},
          {values: us_values, properties: {"amount" => "11"}, invoice_display_name: "US bis"},
          # eu: three filters, one kept untouched
          {values: eu_values, properties: {"amount" => "20"}, invoice_display_name: "EU"},
          {values: eu_values, properties: {"amount" => "21"}, invoice_display_name: "EU bis"},
          {values: eu_values, properties: {"amount" => "22"}, invoice_display_name: "EU ter"},
          # asia: two filters, both removed
          {values: asia_values, properties: {"amount" => "30"}, invoice_display_name: "Asia"},
          {values: asia_values, properties: {"amount" => "31"}, invoice_display_name: "Asia bis"}
        ]
      end

      let(:after) do
        [
          {values: us_values, properties: {"amount" => "15"}, invoice_display_name: "US"},
          {values: eu_values, properties: {"amount" => "20"}, invoice_display_name: "EU"},
          {values: ca_values, properties: {"amount" => "40"}, invoice_display_name: "CA"}
        ]
      end

      # us repriced, eu kept, asia removed, ca added: four predicates touched, so four
      # jobs. Seven `before` filters collapse to four because a job targets a predicate.
      it "enqueues one job per touched predicate, none dropped" do
        expect {
          described_class.call(charge:, before:, after:)
        }.to have_enqueued_job(ChargeFilters::CascadeJob).exactly(4).times
      end

      it "reprices the us predicate" do
        expect {
          described_class.call(charge:, before:, after:)
        }.to have_enqueued_job(ChargeFilters::CascadeJob).with(
          charge.id, "update", us_values, {"amount" => "10"}, {"amount" => "15"}, "US"
        )
      end

      # Untouched properties still need the job: it is what discards the duplicates
      it "cascades the eu predicate even though the kept filter is unchanged" do
        expect {
          described_class.call(charge:, before:, after:)
        }.to have_enqueued_job(ChargeFilters::CascadeJob).with(
          charge.id, "update", eu_values, {"amount" => "20"}, {"amount" => "20"}, "EU"
        )
      end

      it "destroys the asia predicate once" do
        expect {
          described_class.call(charge:, before:, after:)
        }.to have_enqueued_job(ChargeFilters::CascadeJob).with(
          charge.id, "destroy", asia_values, {"amount" => "30"}, nil, "Asia"
        ).once
      end

      it "creates the new ca predicate" do
        expect {
          described_class.call(charge:, before:, after:)
        }.to have_enqueued_job(ChargeFilters::CascadeJob).with(
          charge.id, "create", ca_values, nil, {"amount" => "40"}, "CA"
        )
      end
    end

    context "with a mix of create, update, destroy and unchanged" do
      let(:asia_values) { {"region" => ["asia"]} }
      let(:ca_values) { {"region" => ["ca"]} }

      let(:before) do
        [
          {values: us_values, properties: {"amount" => "10"}, invoice_display_name: "US"},
          {values: eu_values, properties: {"amount" => "20"}, invoice_display_name: "EU"},
          {values: asia_values, properties: {"amount" => "30"}, invoice_display_name: "Asia"}
        ]
      end

      let(:after) do
        [
          {values: us_values, properties: {"amount" => "10"}, invoice_display_name: "US"},   # unchanged
          {values: eu_values, properties: {"amount" => "25"}, invoice_display_name: "EU"},   # update
          {values: ca_values, properties: {"amount" => "40"}, invoice_display_name: "CA"}    # create
          # asia removed → destroy
        ]
      end

      it "enqueues exactly one job per change and skips the unchanged filter" do
        expect {
          described_class.call(charge:, before:, after:)
        }.to have_enqueued_job(ChargeFilters::CascadeJob).exactly(3).times
      end

      it "enqueues the update job for the modified filter" do
        expect {
          described_class.call(charge:, before:, after:)
        }.to have_enqueued_job(ChargeFilters::CascadeJob).with(
          charge.id, "update", eu_values, {"amount" => "20"}, {"amount" => "25"}, "EU"
        )
      end

      it "enqueues the create job for the new filter" do
        expect {
          described_class.call(charge:, before:, after:)
        }.to have_enqueued_job(ChargeFilters::CascadeJob).with(
          charge.id, "create", ca_values, nil, {"amount" => "40"}, "CA"
        )
      end

      it "enqueues the destroy job for the removed filter" do
        expect {
          described_class.call(charge:, before:, after:)
        }.to have_enqueued_job(ChargeFilters::CascadeJob).with(
          charge.id, "destroy", asia_values, {"amount" => "30"}, nil, "Asia"
        )
      end
    end
  end
end
