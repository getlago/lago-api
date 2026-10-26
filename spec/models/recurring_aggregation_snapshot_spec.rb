# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecurringAggregationSnapshot do
  subject(:snapshot) { build(:recurring_aggregation_snapshot) }

  describe "associations" do
    it do
      expect(snapshot).to belong_to(:organization)
      expect(snapshot).to belong_to(:subscription)
      expect(snapshot).to belong_to(:charge)
      expect(snapshot).to belong_to(:charge_filter).optional
      expect(snapshot).to belong_to(:billable_metric)
    end
  end

  describe "validations" do
    it do
      expect(snapshot).to validate_presence_of(:to_datetime)
      expect(snapshot).to validate_presence_of(:watermark)
      expect(snapshot).to validate_numericality_of(:units)
    end
  end

  describe "unique index" do
    let(:existing) { create(:recurring_aggregation_snapshot, grouped_by:) }
    let(:grouped_by) { {} }
    let(:duplicate_to_datetime) { existing.to_datetime }
    let(:duplicate) do
      build(
        :recurring_aggregation_snapshot,
        organization: existing.organization,
        subscription: existing.subscription,
        charge: existing.charge,
        charge_filter: existing.charge_filter,
        grouped_by: existing.grouped_by,
        to_datetime: duplicate_to_datetime
      )
    end

    context "without charge filter" do
      it "rejects a second snapshot for the same period, treating NULL filters as equal" do
        expect { duplicate.save! }.to raise_error(ActiveRecord::RecordNotUnique)
      end
    end

    context "with grouped_by" do
      let(:grouped_by) { {"region" => "eu"} }

      it "rejects a second snapshot for the same group" do
        expect { duplicate.save! }.to raise_error(ActiveRecord::RecordNotUnique)
      end
    end

    context "with a different period" do
      let(:duplicate_to_datetime) { existing.to_datetime + 1.month }

      it "accepts the snapshot" do
        expect { duplicate.save! }.not_to raise_error
      end
    end
  end
end
