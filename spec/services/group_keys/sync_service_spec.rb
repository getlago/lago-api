# frozen_string_literal: true

require "rails_helper"

RSpec.describe GroupKeys::SyncService do
  subject(:sync_service) { described_class.new(owner:, properties:) }

  let(:organization) { create(:organization) }
  let(:charge) { create(:standard_charge, organization:) }
  let(:owner) { charge }

  describe "#call" do
    context "when creating pricing group keys" do
      let(:properties) { {"pricing_group_keys" => ["region", "country"]} }

      it "creates group key records" do
        expect { sync_service.call }.to change(GroupKey, :count).by(2)

        keys = charge.group_keys.pricing
        expect(keys.pluck(:key)).to match_array(["region", "country"])
      end
    end

    context "when creating presentation group keys" do
      let(:properties) { {"presentation_group_keys" => ["department", "project"]} }

      it "creates group key records" do
        expect { sync_service.call }.to change(GroupKey, :count).by(2)

        keys = charge.group_keys.presentation
        expect(keys.pluck(:key)).to match_array(["department", "project"])
      end
    end

    context "when creating both pricing and presentation group keys" do
      let(:properties) do
        {
          "pricing_group_keys" => ["region"],
          "presentation_group_keys" => ["department"]
        }
      end

      it "creates both types of group key records" do
        expect { sync_service.call }.to change(GroupKey, :count).by(2)

        expect(charge.group_keys.pricing.pluck(:key)).to eq(["region"])
        expect(charge.group_keys.presentation.pluck(:key)).to eq(["department"])
      end
    end

    context "when removing keys" do
      let(:properties) { {"pricing_group_keys" => ["region"]} }

      before do
        create(:group_key, organization:, charge:, key: "region", key_type: "pricing")
        create(:group_key, organization:, charge:, key: "country", key_type: "pricing")
      end

      it "soft-deletes removed keys" do
        expect { sync_service.call }.to change { charge.group_keys.pricing.count }.from(2).to(1)

        expect(charge.group_keys.pricing.pluck(:key)).to eq(["region"])
        expect(GroupKey.unscoped.where(charge:, key: "country").first.deleted_at).to be_present
      end
    end

    context "when keys are unchanged" do
      let(:properties) { {"pricing_group_keys" => ["region", "country"]} }

      before do
        create(:group_key, organization:, charge:, key: "region", key_type: "pricing")
        create(:group_key, organization:, charge:, key: "country", key_type: "pricing")
      end

      it "does not create or remove any keys" do
        expect { sync_service.call }.not_to change(GroupKey.unscoped, :count)
      end
    end

    context "when properties are empty" do
      let(:properties) { {} }

      it "does not create any keys" do
        expect { sync_service.call }.not_to change(GroupKey, :count)
      end
    end

    context "when owner is a ChargeFilter" do
      let(:charge_filter) { create(:charge_filter, charge:) }
      let(:owner) { charge_filter }
      let(:properties) { {"pricing_group_keys" => ["region"]} }

      it "creates group key records with charge_filter reference" do
        sync_service.call

        group_key = charge_filter.group_keys.first
        expect(group_key.charge).to eq(charge)
        expect(group_key.charge_filter).to eq(charge_filter)
        expect(group_key.key).to eq("region")
      end
    end
  end
end
