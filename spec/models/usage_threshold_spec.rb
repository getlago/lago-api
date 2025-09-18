# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageThreshold do
  subject(:usage_threshold) { build(:usage_threshold) }

  it_behaves_like "paper_trail traceable"

  it { is_expected.to belong_to(:organization) }
  it { is_expected.to have_many(:applied_usage_thresholds) }
  it { is_expected.to have_many(:invoices).through(:applied_usage_thresholds) }

  it { is_expected.to validate_numericality_of(:amount_cents).is_greater_than(0) }

  describe "default scope" do
    let!(:deleted_usage_threshold) { create(:usage_threshold, :deleted) }

    it "only returns non-deleted usage_threshold objects" do
      expect(described_class.all).to eq([])
      expect(described_class.unscoped.discarded).to eq([deleted_usage_threshold])
    end
  end

  describe "invoice_name" do
    subject(:usage_threshold) { build(:usage_threshold, threshold_display_name:) }

    let(:threshold_display_name) { "Threshold Display Name" }

    it { expect(usage_threshold.invoice_name).to eq(threshold_display_name) }

    context "when threshold display name is null" do
      let(:threshold_display_name) { nil }

      it { expect(usage_threshold.invoice_name).to eq(I18n.t("invoice.usage_threshold")) }
    end
  end
end
