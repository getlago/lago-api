# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChargeFilters::CascadeService do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:billable_metric) { create(:billable_metric, organization:) }
  let(:bm_filter) { create(:billable_metric_filter, billable_metric:, key: "region", values: %w[us eu]) }
  let(:parent_charge) { create(:standard_charge, plan: parent_plan, billable_metric:, properties: {amount: "0"}) }
  let(:child_charge) { create(:standard_charge, plan: child_plan, billable_metric:, parent: parent_charge, properties: {amount: "0"}) }
  # The override deep-copies the plan's filters, code included, so both sides hold the same one
  let(:us_code) { "region_us_1a2b3c4d" }
  let(:child_filter) do
    filter = create(:charge_filter, charge: child_charge, invoice_display_name: "US region", properties: {amount: "10"}, code: us_code)
    create(:charge_filter_value, charge_filter: filter, billable_metric_filter: bm_filter, values: ["us"])
    filter
  end

  let_it_be(:parent_plan) { create(:plan, organization:) }
  let_it_be(:child_plan) { create(:plan, organization:, parent: parent_plan) }

  before do
    create(:subscription, plan: child_plan, status: :active)

    parent_filter = create(:charge_filter, charge: parent_charge, invoice_display_name: "US region", properties: {amount: "10"}, code: us_code)
    create(:charge_filter_value, charge_filter: parent_filter, billable_metric_filter: bm_filter, values: ["us"])

    child_filter
  end

  describe "#call" do
    context "with update action" do
      subject(:service) do
        described_class.call(
          charge: parent_charge,
          action: "update",
          filter_values: {"region" => ["us"]},
          old_properties: {"amount" => "10"},
          new_properties: {"amount" => "15"},
          invoice_display_name: "US region updated",
          parent_code: us_code
        )
      end

      it "updates the matching child filter" do
        service

        expect(child_filter.reload).to have_attributes(
          properties: {"amount" => "15"},
          invoice_display_name: "US region updated"
        )
      end

      context "with several children" do
        let(:other_child_plan) { create(:plan, organization:, parent: parent_plan) }
        let(:other_child_charge) do
          create(:standard_charge, plan: other_child_plan, billable_metric:, parent: parent_charge, properties: {amount: "0"})
        end

        let(:other_child_filter) do
          create(:charge_filter, charge: other_child_charge, invoice_display_name: "US region", properties: {amount: "10"}, code: us_code)
        end

        # A filter on a different value that must not be matched by the cascade
        let(:unrelated_filter) do
          create(:charge_filter, charge: child_charge, invoice_display_name: "EU region", properties: {amount: "99"})
        end

        before do
          create(:subscription, plan: other_child_plan, status: :active)
          create(:charge_filter_value, charge_filter: other_child_filter, billable_metric_filter: bm_filter, values: ["us"])
          create(:charge_filter_value, charge_filter: unrelated_filter, billable_metric_filter: bm_filter, values: ["eu"])
        end

        it "updates the matching filter on every child and leaves others untouched" do
          service

          expect(child_filter.reload.properties).to eq({"amount" => "15"})
          expect(other_child_filter.reload.properties).to eq({"amount" => "15"})
          expect(unrelated_filter.reload.properties).to eq({"amount" => "99"})
        end
      end

      context "when child filter was customized" do
        let!(:child_filter) do
          filter = create(:charge_filter, charge: child_charge, invoice_display_name: "Custom", properties: {amount: "99"}, code: us_code)
          create(:charge_filter_value, charge_filter: filter, billable_metric_filter: bm_filter, values: ["us"])
          filter
        end

        it "does not update the customized filter properties" do
          service

          expect(child_filter.reload.properties).to eq({"amount" => "99"})
        end

        context "when new properties include pricing_group_keys" do
          subject(:service) do
            described_class.call(
              charge: parent_charge,
              action: "update",
              filter_values: {"region" => ["us"]},
              old_properties: {"amount" => "10"},
              new_properties: {"amount" => "15", "pricing_group_keys" => ["agent_name"]},
              invoice_display_name: "US region updated",
              parent_code: us_code
            )
          end

          it "cascades pricing_group_keys even though properties are customized" do
            service

            expect(child_filter.reload.properties).to eq({"amount" => "99", "pricing_group_keys" => ["agent_name"]})
          end
        end

        context "when new properties remove pricing_group_keys" do
          subject(:service) do
            described_class.call(
              charge: parent_charge,
              action: "update",
              filter_values: {"region" => ["us"]},
              old_properties: {"amount" => "10", "pricing_group_keys" => ["old_key"]},
              new_properties: {"amount" => "15"},
              invoice_display_name: "US region updated",
              parent_code: us_code
            )
          end

          let!(:child_filter) do
            filter = create(
              :charge_filter,
              charge: child_charge,
              invoice_display_name: "Custom",
              properties: {"amount" => "99", "pricing_group_keys" => ["old_key"]},
              code: us_code
            )
            create(:charge_filter_value, charge_filter: filter, billable_metric_filter: bm_filter, values: ["us"])
            filter
          end

          it "removes pricing_group_keys from the customized filter" do
            service

            expect(child_filter.reload.properties).to eq({"amount" => "99"})
          end
        end
      end

      context "when child has no matching filter" do
        before do
          child_charge.filters.each do |f|
            f.values.update_all(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
            f.discard!
          end
        end

        it "succeeds without error" do
          expect(service).to be_success
        end
      end

      # Deliberately loud. The job carries no identity, so the filters still missing a code
      # surface as dead jobs naming the charge and the predicate, which is the list to fix.
      context "when the plan's filter has no code" do
        subject(:service) do
          described_class.call(
            charge: parent_charge,
            action: "update",
            filter_values: {"region" => ["us"]},
            old_properties: {"amount" => "10"},
            new_properties: {"amount" => "15"},
            invoice_display_name: "US region updated"
          )
        end

        it "raises rather than guessing at the predicate" do
          expect { service }.to raise_error(
            described_class::MissingParentCode, /#{parent_charge.id}.*region/
          )
        end

        it "leaves the child filter on the old price" do
          expect { service }.to raise_error(described_class::MissingParentCode)

          expect(child_filter.reload.properties).to eq({"amount" => "10"})
        end
      end

      # The predicate reaches whichever filter happens to sit on it; the code reaches the one
      # the plan actually changed
      context "when a filter holds the parent's code on another predicate" do
        subject(:service) do
          described_class.call(
            charge: parent_charge,
            action: "update",
            filter_values: {"region" => ["us"]},
            old_properties: {"amount" => "10"},
            new_properties: {"amount" => "15"},
            invoice_display_name: "US region updated",
            parent_code: "the-parents-code"
          )
        end

        let(:coded_filter) do
          filter = create(:charge_filter, charge: child_charge, code: "the-parents-code", properties: {amount: "10"})
          create(:charge_filter_value, charge_filter: filter, billable_metric_filter: bm_filter, values: ["eu"])
          filter
        end

        before { coded_filter }

        it "updates the filter holding the code" do
          service

          expect(coded_filter.reload.properties).to eq({"amount" => "15"})
        end

        it "leaves the one merely sharing the predicate alone" do
          service

          expect(child_filter.reload.properties).to eq({"amount" => "10"})
        end
      end
    end

    context "with create action" do
      subject(:service) do
        described_class.call(
          charge: parent_charge,
          action: "create",
          filter_values: {"region" => ["eu"]},
          new_properties: {"amount" => "20"},
          invoice_display_name: "EU region"
        )
      end

      it "creates the filter on the child charge" do
        expect { service }.to change { child_charge.filters.reload.count }.by(1)

        new_filter = child_charge.filters.find_by(invoice_display_name: "EU region")
        expect(new_filter.properties).to eq({"amount" => "20"})
        expect(new_filter.to_h).to eq({"region" => ["eu"]})
      end

      # The code links a plan's filter to the copies on its overrides, so the child has to take
      # the parent's rather than derive one from its own values
      it "gives the new child filter the parent's code" do
        described_class.call(
          charge: parent_charge,
          action: "create",
          filter_values: {"region" => ["eu"]},
          new_properties: {"amount" => "20"},
          invoice_display_name: "EU region",
          parent_code: "a-code-only-the-parent-could-have"
        )

        expect(child_charge.filters.find_by(invoice_display_name: "EU region").code)
          .to eq("a-code-only-the-parent-could-have")
      end

      # The parent is still waiting on the backfill. Deriving a code here would hand the child
      # one the parent never gets, and the backfill would then never pair them.
      it "leaves the code nil when the parent has none yet" do
        service

        expect(child_charge.filters.find_by(invoice_display_name: "EU region").code).to be_nil
      end

      context "when child already has the filter" do
        subject(:service) do
          described_class.call(
            charge: parent_charge,
            action: "create",
            filter_values: {"region" => ["eu"]},
            new_properties: {"amount" => "20"},
            invoice_display_name: "EU region",
            parent_code: "the-parents-code"
          )
        end

        let(:existing) do
          filter = create(:charge_filter, charge: child_charge, properties: {amount: "20"})
          create(:charge_filter_value, charge_filter: filter, billable_metric_filter: bm_filter, values: ["eu"])
          filter
        end

        before { existing }

        it "does not create a duplicate" do
          expect { service }.not_to change { child_charge.filters.reload.count }
        end

        # The filter got there before the plan had one. This is the only moment we can say the
        # two are the same, and without it the cascade could never reach this one again.
        it "links it to the plan's filter" do
          service

          expect(existing.reload.code).to eq("the-parents-code")
        end

        # Which of the two adopts the code decides which one bills from then on, and row order is
        # not a way to decide that. The pair has to be cleaned up first.
        context "when the child holds the predicate twice" do
          before do
            other = create(:charge_filter, charge: child_charge, properties: {amount: "35"})
            create(:charge_filter_value, charge_filter: other, billable_metric_filter: bm_filter, values: ["eu"])
          end

          it "raises rather than linking one at random" do
            expect { service }.to raise_error(
              described_class::DuplicatePredicate, /#{child_charge.id}/
            )
          end
        end

        context "when it already has a code of its own" do
          let(:existing) do
            filter = create(:charge_filter, charge: child_charge, properties: {amount: "20"}, code: "its_own_code_1a2b3c4d")
            create(:charge_filter_value, charge_filter: filter, billable_metric_filter: bm_filter, values: ["eu"])
            filter
          end

          # Born on the override with an identity of its own, so it is nobody's copy
          it "leaves the code alone" do
            service

            expect(existing.reload.code).to eq("its_own_code_1a2b3c4d")
          end

          # Nor is the plan's filter created beside it. The code does not reach this filter but the
          # predicate does, and that is what keeps a create from duplicating. Narrowing the predicate
          # lookup to codeless filters would hide this one and land a second filter on the predicate.
          it "does not create a second filter on the same predicate" do
            expect { service }.not_to change { child_charge.filters.reload.count }
          end
        end
      end

      # Two cascade jobs for the same filter both read the child's filters before either of
      # them writes. The predicate lookup cannot pair them up once a billable metric change
      # shortened one side, so without the code both go on to create.
      context "when a copy already holds the parent's code" do
        subject(:service) do
          described_class.call(
            charge: parent_charge,
            action: "create",
            filter_values: {"region" => ["eu"]},
            new_properties: {"amount" => "20"},
            invoice_display_name: "EU region",
            parent_code: "the-parents-code"
          )
        end

        # No values, so the predicate lookup passes it by and only the code identifies it
        let(:copy) { create(:charge_filter, charge: child_charge, code: "the-parents-code", properties: {amount: "20"}) }

        before { copy }

        it "does not create a second copy" do
          expect { service }.not_to change { child_charge.filters.reload.count }
        end

        it "leaves the copy untouched" do
          expect { service }.not_to change { copy.reload.updated_at }
        end
      end

      # The lookup ran before the other job committed, so the insert is the first thing to see the
      # conflict. Left to fail on purpose: swallowing it would hide filters that still need
      # cleaning up. needs manual retry
      context "when another job commits the copy mid-flight" do
        let(:racing) do
          described_class.new(
            charge: parent_charge,
            action: "create",
            filter_values: {"region" => ["eu"]},
            new_properties: {"amount" => "20"},
            invoice_display_name: "EU region",
            parent_code: "the-parents-code"
          )
        end

        before do
          create(:charge_filter, charge: child_charge, code: "the-parents-code", properties: {amount: "20"})
          allow(racing).to receive(:child_filters_holding_parent_code).and_return({})
        end

        it "lets the unique index reject it" do
          expect { racing.call }.to raise_error(ActiveRecord::RecordNotUnique)
        end
      end

      context "when the billable metric filter key no longer exists" do
        subject(:service) do
          described_class.call(
            charge: parent_charge,
            action: "create",
            filter_values: {"country" => ["fr"]},
            new_properties: {"amount" => "20"},
            invoice_display_name: "FR country"
          )
        end

        it "does not create a child filter" do
          expect { service }.not_to change { child_charge.filters.reload.count }
          expect(service).to be_success
        end
      end

      context "when the billable metric filter values were trimmed" do
        subject(:service) do
          described_class.call(
            charge: parent_charge,
            action: "create",
            filter_values: {"region" => %w[eu apac]},
            new_properties: {"amount" => "20"},
            invoice_display_name: "EU region"
          )
        end

        it "creates the filter with only the values still allowed" do
          expect { service }.to change { child_charge.filters.reload.count }.by(1)

          new_filter = child_charge.filters.find_by(invoice_display_name: "EU region")
          expect(new_filter.to_h).to eq({"region" => ["eu"]})
        end
      end

      context "when none of the snapshot values are still allowed" do
        subject(:service) do
          described_class.call(
            charge: parent_charge,
            action: "create",
            filter_values: {"region" => ["apac"]},
            new_properties: {"amount" => "20"},
            invoice_display_name: "APAC region"
          )
        end

        it "does not create a child filter" do
          expect { service }.not_to change { child_charge.filters.reload.count }
          expect(service).to be_success
        end
      end
    end

    context "with destroy action" do
      subject(:service) do
        described_class.call(
          charge: parent_charge,
          action: "destroy",
          filter_values: {"region" => ["us"]}
        )
      end

      context "when the child holds the parent's code" do
        subject(:service) do
          described_class.call(
            charge: parent_charge,
            action: "destroy",
            filter_values: {"region" => ["us"]},
            parent_code: "the-parents-code"
          )
        end

        before { child_filter.update!(code: "the-parents-code") }

        it "discards the matching child filter and its values" do
          service

          expect(child_filter.reload).to be_discarded
          expect(child_filter.values.kept).to be_empty
        end
      end

      # Nothing identifies which filter this is, and the one on the predicate may well belong
      # to the customer rather than to the plan. Left alone rather than discarded on a guess.
      context "when nothing holds the parent's code" do
        it "leaves the filter sharing the predicate alone" do
          service

          expect(child_filter.reload).not_to be_discarded
        end
      end

      # A billable metric change shortened the coded filter's predicate, so the two no longer
      # describe the same thing and the predicate now points at the wrong one
      context "when a filter holds the parent's code on another predicate" do
        subject(:service) do
          described_class.call(
            charge: parent_charge,
            action: "destroy",
            filter_values: {"region" => ["us"]},
            parent_code: "the-parents-code"
          )
        end

        let(:coded_filter) do
          filter = create(:charge_filter, charge: child_charge, code: "the-parents-code", properties: {amount: "10"})
          create(:charge_filter_value, charge_filter: filter, billable_metric_filter: bm_filter, values: ["eu"])
          filter
        end

        before { coded_filter }

        it "discards the filter holding the code" do
          service

          expect(coded_filter.reload).to be_discarded
        end

        it "leaves the one merely sharing the predicate alone" do
          service

          expect(child_filter.reload).not_to be_discarded
        end
      end

      context "when child has no matching filter" do
        before do
          child_charge.filters.each do |f|
            f.values.update_all(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
            f.discard!
          end
        end

        it "succeeds without error" do
          expect(service).to be_success
        end
      end
    end

    context "when child charge has no active subscription" do
      subject(:service) do
        described_class.call(
          charge: parent_charge,
          action: "update",
          filter_values: {"region" => ["us"]},
          old_properties: {"amount" => "10"},
          new_properties: {"amount" => "15"},
          invoice_display_name: "US region",
          parent_code: us_code
        )
      end

      before do
        Subscription.update_all(status: :terminated) # rubocop:disable Rails/SkipsModelValidations
      end

      it "does not update the child filter" do
        service

        expect(child_filter.reload.properties).to eq({"amount" => "10"})
      end

      # A missing code costs nothing when there is nobody to cascade to, so it is not reported
      it "does not report a missing code either" do
        expect {
          described_class.call(
            charge: parent_charge,
            action: "update",
            filter_values: {"region" => ["us"]},
            old_properties: {"amount" => "10"},
            new_properties: {"amount" => "15"},
            invoice_display_name: "US region"
          )
        }.not_to raise_error
      end
    end
  end
end
