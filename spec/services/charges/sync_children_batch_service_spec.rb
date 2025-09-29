# frozen_string_literal: true

require "rails_helper"

RSpec.describe Charges::SyncChildrenBatchService do
  subject(:sync_service) { described_class.new(child_ids:, charge:) }

  let(:organization) { create(:organization) }
  let(:parent_plan) { create(:plan, organization:) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:charge) { create(:standard_charge, organization:, plan: parent_plan, billable_metric:) }

  let(:child_plan1) { create(:plan, organization:, parent: parent_plan) }
  let(:child_plan2) { create(:plan, organization:, parent: parent_plan) }
  let(:child_plan3) { create(:plan, organization:, parent: parent_plan) }
  let(:child_ids) { [child_plan1.id, child_plan2.id, child_plan3.id] }

  before do
    charge
  end

  describe "#call" do
    context "when charge is not found" do
      let(:charge) { nil }

      it "returns a not found failure" do
        result = sync_service.call

        expect(result).not_to be_success
        expect(result.error.error_code).to eq("charge_not_found")
      end

      it "does not create any charges" do
        expect { sync_service.call }.not_to change(Charge, :count)
      end
    end

    context "when child_ids is empty" do
      let(:child_ids) { [] }

      it "returns a successful result" do
        result = sync_service.call

        expect(result).to be_success
      end

      it "does not create any charges" do
        expect { sync_service.call }.not_to change(Charge, :count)
      end
    end

    context "when child plans exist and no child charges exist" do
      it "creates child charges with correct attributes" do
        result = sync_service.call
        expect(result).to be_success

        child_charges = Charge.where(parent_id: charge.id)
        expect(child_charges.count).to eq(3)

        child_charges.each do |child_charge|
          expect(child_charge).to have_attributes(
            organization_id: organization.id,
            billable_metric_id: billable_metric.id,
            parent_id: charge.id,
            charge_model: charge.charge_model,
            pay_in_advance: charge.pay_in_advance,
            prorated: charge.prorated,
            properties: charge.properties
          )
        end
      end

      it "creates charges for the correct child plans" do
        sync_service.call

        child_plan1_charge = child_plan1.charges.find_by(parent_id: charge.id)
        child_plan2_charge = child_plan2.charges.find_by(parent_id: charge.id)
        child_plan3_charge = child_plan3.charges.find_by(parent_id: charge.id)

        expect(child_plan1_charge).to be_present
        expect(child_plan2_charge).to be_present
        expect(child_plan3_charge).to be_present
      end
    end

    context "when some child charges already exist" do
      let(:existing_child_charge) do
        create(:standard_charge, organization:, plan: child_plan1, billable_metric:, parent_id: charge.id)
      end

      before do
        existing_child_charge
      end

      it "only creates charges for child plans without existing charges" do
        expect { sync_service.call }.to change(Charge, :count).by(2)

        child_plan2_charge = child_plan2.charges.find_by(parent_id: charge.id)
        child_plan3_charge = child_plan3.charges.find_by(parent_id: charge.id)

        expect(child_plan2_charge).to be_present
        expect(child_plan3_charge).to be_present
      end

      it "does not create duplicate charges" do
        sync_service.call

        child_plan1_charges = child_plan1.charges.where(parent_id: charge.id)
        expect(child_plan1_charges.count).to eq(1)
        expect(child_plan1_charges.first).to eq(existing_child_charge)
      end
    end

    context "when all child charges already exist" do
      let(:existing_child_charge1) do
        create(:standard_charge, organization:, plan: child_plan1, billable_metric:, parent_id: charge.id)
      end
      let(:existing_child_charge2) do
        create(:standard_charge, organization:, plan: child_plan2, billable_metric:, parent_id: charge.id)
      end
      let(:existing_child_charge3) do
        create(:standard_charge, organization:, plan: child_plan3, billable_metric:, parent_id: charge.id)
      end

      before do
        existing_child_charge1
        existing_child_charge2
        existing_child_charge3
      end


      it "does not create any new charges" do
        expect { sync_service.call }.not_to change(Charge, :count)
      end

      it "returns a successful result" do
        result = sync_service.call

        expect(result).to be_success
      end
    end

    context "when child plans have other charges" do
      let!(:existing_child_charge1) do
        create(:standard_charge, organization:, plan: child_plan1, billable_metric:)
      end

      it "creates charges for all child plans" do
        expect { sync_service.call }.to change(Charge, :count).by(3)
        expect(child_plan1.charges.count).to eq(2)
        expect(child_plan2.charges.count).to eq(1)
        expect(child_plan3.charges.count).to eq(1)
      end
    end

    context "when some child_ids do not match existing child plans" do
      let(:non_existent_id) { SecureRandom.uuid }
      let(:child_ids) { [child_plan1.id, non_existent_id, child_plan2.id] }

      it "creates charges only for existing child plans" do
        expect { sync_service.call }.to change(Charge, :count).by(2)
      end

      it "creates charges for the correct child plans" do
        sync_service.call

        child_plan1_charge = child_plan1.charges.find_by(parent_id: charge.id)
        child_plan2_charge = child_plan2.charges.find_by(parent_id: charge.id)
        child_plan3_charge = child_plan3.charges.find_by(parent_id: charge.id)

        expect(child_plan1_charge).to be_present
        expect(child_plan2_charge).to be_present
        expect(child_plan3_charge).to be_nil
      end
    end

    context "when Charges::CreateService fails" do
      before do
        allow(Charges::CreateService).to receive(:call!).and_raise(ActiveRecord::RecordInvalid.new(charge))
      end

      it "raises the error" do
        expect { sync_service.call }.to raise_error(ActiveRecord::RecordInvalid)
      end
    end

    context "when charge has complex properties" do
      let(:charge) do
        create(
          :graduated_charge,
          organization:,
          plan: parent_plan,
          billable_metric:,
          pay_in_advance: true,
          prorated: false,
          invoice_display_name: "Complex Charge"
        )
      end

      it "copies all charge attributes to child charges" do
        sync_service.call

        child_charge = child_plan1.charges.find_by(parent_id: charge.id)
        expect(child_charge).to have_attributes(
          pay_in_advance: true,
          prorated: false,
          invoice_display_name: "Complex Charge"
        )
        expect(child_charge.properties).to include(
          "graduated_ranges" => [
            {"from_value" => 0, "to_value" => 10, "per_unit_amount" => "0", "flat_amount" => "200"},
            {"from_value" => 11, "to_value" => nil, "per_unit_amount" => "0", "flat_amount" => "300"}
          ]
        )
      end
    end
  end
end
